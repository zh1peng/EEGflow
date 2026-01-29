classdef Pipeline < handle
    % PIPELINE  Spec-driven pipeline runner (context + registry + steps)
    %
    % Core idea:
    %   - context is the only payload (context.EEG / context.cfg / context.qc / context.runtime / ...)
    %   - steps are declarative specs: {id,name,op,args,when}
    %   - registry is a containers.Map(op -> wrapper_handle)
    %
    % Wrapper signature:
    %   context = wrapper(context, args, meta)
    %
    % meta provides: step, step_index, validate_only, logger

    properties
        context            % struct payload
        registry           % containers.Map: op(string) -> function_handle
        steps              % struct array: id,name,op,args,when

        LogFile
        ErrFile

        LoggerFn           % function_handle: @(msg) ...
        ErrLoggerFn        % function_handle: @(msg) ...

        WhenEvaluatorFn    % optional: evaluate string "when" (for JSON-serializable specs)
                           % signature: tf = WhenEvaluatorFn(exprString, context)
    end

    methods
        function obj = Pipeline(context, registry)
            if nargin < 1 || isempty(context), context = struct(); end
            obj.context = obj.local_normalize_context(context);

            if nargin < 2 || isempty(registry)
                obj.registry = containers.Map('KeyType','char','ValueType','any');
            else
                obj.registry = registry;
            end

            cfg = obj.context.cfg;
            obj.LogFile = obj.local_get(cfg, {'LogFile'}, 'pipeline.log');
            obj.ErrFile = obj.local_get(cfg, {'error_LogFile'}, 'pipeline_error.log');

            % Default logger: fprintf (you can inject logPrint-based logger later)
            obj.LoggerFn    = @(msg) fprintf('%s\n', msg);
            obj.ErrLoggerFn = @(msg) fprintf(2, '%s\n', msg);

            obj.WhenEvaluatorFn = [];

            obj.steps = struct('id', {}, 'name', {}, 'op', {}, 'args', {}, 'when', {});
            obj.log(sprintf('=== Pipeline start (%s) ===', datestr(now, 31)));
        end

        function obj = setIO(obj, logFile, errFile)
            if nargin >= 2 && ~isempty(logFile), obj.LogFile = logFile; end
            if nargin >= 3 && ~isempty(errFile), obj.ErrFile = errFile; end
        end

        function obj = setLogger(obj, loggerFn, errLoggerFn)
            if nargin >= 2 && ~isempty(loggerFn), obj.LoggerFn = loggerFn; end
            if nargin >= 3 && ~isempty(errLoggerFn), obj.ErrLoggerFn = errLoggerFn; end
        end

        function obj = setWhenEvaluator(obj, fn)
            % fn: @(exprString, context) -> logical
            obj.WhenEvaluatorFn = fn;
        end

        function obj = register(obj, op, fn)
            % op can contain '.', '-', '/', etc.
            op = char(op);
            if ~isa(fn, 'function_handle')
                error('Pipeline:register', 'registry value must be function_handle');
            end
            obj.registry(op) = fn;
        end

        function obj = add(obj, opName, varargin)
            % ADD Add a step. Robust to: add(op, structArgs..., 'k',v, ..., 'name',..., 'when',...)
            if nargin < 2 || isempty(opName)
                error('Pipeline:add', 'opName is required.');
            end
            opName = char(opName);

            % --- 1) Extract leading positional struct(s) ---
            posArgs = struct();
            nvArgs  = varargin;

            k = 1;
            while k <= numel(nvArgs) && isstruct(nvArgs{k})
                posArgs = obj.local_merge_struct(posArgs, nvArgs{k}); % later struct overrides earlier struct
                k = k + 1;
            end
            nvArgs = nvArgs(k:end);

            % --- 2) Parse reserved keys (name/when/id), keep others in Unmatched as args ---
            p = inputParser;
            p.KeepUnmatched = true;
            addParameter(p, 'name', '', @(x) ischar(x) || isstring(x));
            addParameter(p, 'when', [], @(x) isempty(x) || isa(x,'function_handle') || ischar(x) || isstring(x));
            addParameter(p, 'id',   '', @(x) ischar(x) || isstring(x));

            % Only parse NV part; if nvArgs is empty, this is fine.
            parse(p, nvArgs{:});

            % --- 3) Merge args: Unmatched NV overrides positional struct ---
            stepArgs = obj.local_merge_struct(posArgs, p.Unmatched);

            % --- 4) Resolve id/name ---
            stepId = char(p.Results.id);
            if isempty(stepId), stepId = obj.local_next_id(); end

            stepName = char(p.Results.name);
            if isempty(stepName)
                stepName = sprintf('%s_%s', opName, stepId);
            end

            % --- 5) Construct step ---
            s = struct();
            s.id   = stepId;
            s.name = stepName;
            s.op   = opName;
            s.args = stepArgs;
            s.when = p.Results.when;

            obj.steps(end+1) = s;
        end


        function obj = add_steps(obj, spec)
            % ADD_STEPS Append/replace pipeline steps from spec
            % spec.steps: struct array with at least .op; optionally name/id/args/when
            if ~isstruct(spec) || ~isfield(spec, 'steps')
                error('Pipeline:add_steps', 'spec must be struct with field spec.steps');
            end
            obj.steps = spec.steps;

            % normalize missing fields
            for i = 1:numel(obj.steps)
                if ~isfield(obj.steps(i),'id') || isempty(obj.steps(i).id)
                    obj.steps(i).id = obj.local_next_id();
                end
                if ~isfield(obj.steps(i),'name') || isempty(obj.steps(i).name)
                    obj.steps(i).name = sprintf('%s_%s', obj.steps(i).op, obj.steps(i).id);
                end
                if ~isfield(obj.steps(i),'args') || isempty(obj.steps(i).args)
                    obj.steps(i).args = struct();
                end
                if ~isfield(obj.steps(i),'when')
                    obj.steps(i).when = [];
                end
            end
        end

        function [context, report] = run(obj, varargin)
            % RUN Execute pipeline
            % Options:
            %   'stop_on_error' default true
            %   'max_steps' default inf

            ip = inputParser;
            addParameter(ip, 'stop_on_error', false, @islogical);
            addParameter(ip, 'max_steps', inf, @(x) isnumeric(x) && isscalar(x));
            parse(ip, varargin{:});
            opt = ip.Results;

            t0 = tic;

            obj.context.runtime.run_started_at = datestr(now, 31);
            obj.context.runtime.validate_only = false;
            if ~isfield(obj.context.runtime, 'steps') || isempty(obj.context.runtime.steps)
                obj.context.runtime.steps = obj.local_empty_steps();
            end

            report = struct('ok', true, 'errors', {{}}, 'n_steps', numel(obj.steps), 'total_sec', NaN);

            n = min(numel(obj.steps), opt.max_steps);

            for i = 1:n
                step = obj.steps(i);

                % ---- when gate ----
                if ~obj.local_eval_when(step.when, obj.context)
                    obj.log(sprintf('[SKIP] #%d %s (%s)', i, step.name, step.op));
                    obj.context.runtime.steps(end+1) = obj.local_step_record(step, i, 'skipped', 0, []);
                    continue
                end

                % ---- registry lookup ----
                if ~obj.registry.isKey(step.op)
                    ME = MException('Pipeline:UnknownOp', 'Unknown op "%s" (step "%s").', step.op, step.name);
                    obj.err(ME.message);
                    obj.context.runtime.steps(end+1) = obj.local_step_record(step, i, 'error', 0, ME);
                    report.ok = false; report.errors{end+1} = ME;
                    if opt.stop_on_error, break; else, continue; end
                end

                fn = obj.registry(step.op);

                obj.log(sprintf('[RUN]  #%d %s (%s)', i, step.name, step.op));
                tStep = tic;

                meta = struct();
                meta.step = step;
                meta.step_index = i;
                meta.validate_only = false;
                meta.started_at = datestr(now, 31);
                meta.logger = @(msg) obj.log(sprintf('[%s] %s', step.op, msg));

                try
                    % Dry-run responsibility is in wrapper.
                    obj.context = fn(obj.context, step.args, meta);

                    dt = toc(tStep);
                    obj.log(sprintf('[OK]   #%d %s in %.2fs', i, step.name, dt));
                    obj.context.runtime.steps(end+1) = obj.local_step_record(step, i, 'ok', dt, []);

                catch ME
                    dt = toc(tStep);
                    obj.err(sprintf('[FAIL] #%d %s: %s', i, step.name, ME.message));
                    obj.context.runtime.steps(end+1) = obj.local_step_record(step, i, 'error', dt, ME);

                    report.ok = false;
                    report.errors{end+1} = ME;
                    obj.context.runtime.last_error = struct('step', step.name, 'op', step.op, 'id', ME.identifier, 'msg', ME.message);

                    if opt.stop_on_error, break; end
                end
            end

            report.total_sec = toc(t0);
            obj.context.runtime.run_finished_at = datestr(now, 31);
            obj.context = obj.local_strip_init_step(obj.context);
            obj.log(sprintf('=== Pipeline end (%.2fs) ok=%d ===', report.total_sec, report.ok));

            context = obj.context;
        end

        function obj = fromSpec(obj, spec)
            % Backward compatible alias
            obj = obj.add_steps(spec);
        end

        function [context, report] = validate(obj, varargin)
            % VALIDATE Validate pipeline args without executing heavy ops
            % Options:
            %   'stop_on_error' default true
            %   'max_steps' default inf

            ip = inputParser;
            addParameter(ip, 'stop_on_error', true, @islogical);
            addParameter(ip, 'max_steps', inf, @(x) isnumeric(x) && isscalar(x));
            parse(ip, varargin{:});
            opt = ip.Results;

            t0 = tic;
            obj.context.runtime.run_started_at = datestr(now, 31);
            obj.context.runtime.validate_only = true;
            if ~isfield(obj.context.runtime, 'steps') || isempty(obj.context.runtime.steps)
                obj.context.runtime.steps = obj.local_empty_steps();
            end

            report = struct('ok', true, 'errors', {{}}, 'n_steps', numel(obj.steps), 'total_sec', NaN);
            n = min(numel(obj.steps), opt.max_steps);

            for i = 1:n
                step = obj.steps(i);
                if ~obj.local_eval_when(step.when, obj.context)
                    obj.log(sprintf('[SKIP] #%d %s (%s)', i, step.name, step.op));
                    obj.context.runtime.steps(end+1) = obj.local_step_record(step, i, 'skipped', 0, []);
                    continue
                end

                if ~obj.registry.isKey(step.op)
                    ME = MException('Pipeline:UnknownOp', 'Unknown op "%s" (step "%s").', step.op, step.name);
                    obj.err(ME.message);
                    obj.context.runtime.steps(end+1) = obj.local_step_record(step, i, 'error', 0, ME);
                    report.ok = false; report.errors{end+1} = ME;
                    if opt.stop_on_error, break; else, continue; end
                end

                fn = obj.registry(step.op);
                obj.log(sprintf('[VAL]  #%d %s (%s)', i, step.name, step.op));
                tStep = tic;

                meta = struct();
                meta.step = step;
                meta.step_index = i;
                meta.validate_only = true;
                meta.started_at = datestr(now, 31);
                meta.logger = @(msg) obj.log(sprintf('[%s] %s', step.op, msg));

                try
                    obj.context = fn(obj.context, step.args, meta);
                    dt = toc(tStep);
                    obj.log(sprintf('[OK]   #%d %s in %.2fs', i, step.name, dt));
                    obj.context.runtime.steps(end+1) = obj.local_step_record(step, i, 'ok', dt, []);
                catch ME
                    dt = toc(tStep);
                    obj.err(sprintf('[FAIL] #%d %s: %s', i, step.name, ME.message));
                    obj.context.runtime.steps(end+1) = obj.local_step_record(step, i, 'error', dt, ME);
                    report.ok = false; report.errors{end+1} = ME;
                    obj.context.runtime.last_error = struct('step', step.name, 'op', step.op, 'id', ME.identifier, 'msg', ME.message);
                    if opt.stop_on_error, break; end
                end
            end

            report.total_sec = toc(t0);
            obj.context.runtime.run_finished_at = datestr(now, 31);
            obj.context = obj.local_strip_init_step(obj.context);
            obj.log(sprintf('=== Pipeline validate end (%.2fs) ok=%d ===', report.total_sec, report.ok));
            context = obj.context;
        end
    end

    methods (Access = private)
        function c = local_normalize_context(obj, c)
            if ~isfield(c, 'EEG'), c.EEG = []; end
            if ~isfield(c, 'cfg'), c.cfg = struct(); end
            if ~isfield(c, 'qc'), c.qc = struct(); end
            if ~isfield(c, 'artifacts'), c.artifacts = struct(); end
            if ~isfield(c, 'runtime'), c.runtime = struct(); end
            if ~isfield(c.runtime, 'steps') || isempty(c.runtime.steps)
                c.runtime.steps = obj.local_empty_steps();
            end
            if ~isfield(c.runtime, 'id_counter'), c.runtime.id_counter = 0; end
        end

        function v = local_get(~, s, path, default)
            v = default;
            t = s;
            for k = 1:numel(path)
                f = path{k};
                if ~isstruct(t) || ~isfield(t, f), return; end
                t = t.(f);
            end
            v = t;
        end

        function id = local_next_id(obj)
            obj.context.runtime.id_counter = obj.context.runtime.id_counter + 1;
            id = sprintf('S%03d', obj.context.runtime.id_counter);
        end

        function tf = local_eval_when(obj, whenVal, context)
            if isempty(whenVal)
                tf = true;
                return
            end
            if isa(whenVal, 'function_handle')
                tf = logical(whenVal(context));
                return
            end
            if ischar(whenVal) || isstring(whenVal)
                if isempty(obj.WhenEvaluatorFn)
                    error('Pipeline:WhenStringNoEvaluator', ...
                        'Step has string "when" but WhenEvaluatorFn is not set.');
                end
                tf = logical(obj.WhenEvaluatorFn(char(whenVal), context));
                return
            end
            error('Pipeline:BadWhen', '"when" must be function_handle or string/char.');
        end

        function rec = local_step_record(~, step, idx, status, dt, ME)
            rec = struct();
            rec.id = step.id;
            rec.index = idx;
            rec.name = step.name;
            rec.op = step.op;
            rec.status = status;
            rec.dt_sec = dt;
            rec.args = step.args;
            if isempty(ME)
                rec.error = [];
            else
                rec.error = struct('id', ME.identifier, 'msg', ME.message);
            end
        end

        function out = local_merge_struct(~, a, b)
            out = a;
            fb = fieldnames(b);
            for k = 1:numel(fb)
                out.(fb{k}) = b.(fb{k});
            end
        end

        function log(obj, msg)
            % Optionally also write to files if you inject a logger that does that.
            obj.LoggerFn(msg);
            if ~isfield(obj.context.runtime, 'log') || isempty(obj.context.runtime.log)
                obj.context.runtime.log = {};
            end
            obj.context.runtime.log{end+1} = msg;
        end

        function err(obj, msg)
            obj.ErrLoggerFn(msg);
            if ~isfield(obj.context.runtime, 'err') || isempty(obj.context.runtime.err)
                obj.context.runtime.err = {};
            end
            obj.context.runtime.err{end+1} = msg;
        end

        function c = local_strip_init_step(~, c)
            if ~isfield(c, 'runtime') || ~isfield(c.runtime, 'steps') || isempty(c.runtime.steps)
                return;
            end
            if isfield(c.runtime.steps(1), 'status') && strcmp(c.runtime.steps(1).status, 'init')
                c.runtime.steps(1) = [];
            end
        end

        function s = local_empty_steps(~)
            s = struct('id', {}, 'index', {}, 'name', {}, 'op', {}, 'status', {}, ...
                'dt_sec', {}, 'args', {}, 'error', {});
        end
    end
end
