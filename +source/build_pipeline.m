function [pipe, state, cfg] = build_pipeline(cfgIn, varargin)
%BUILD_PIPELINE Build a generic source-space Pipeline from config.
%
% Usage:
%   [pipe, state, cfg] = source.build_pipeline(cfgOrPath);
%   [pipe, state, cfg] = source.build_pipeline(cfgOrPath, 'State', state);

    ip = inputParser;
    addParameter(ip, 'State', struct(), @isstruct);
    addParameter(ip, 'Registry', [], @(x) isempty(x) || isa(x, 'containers.Map'));
    addParameter(ip, 'WhenEvaluatorFn', [], @(x) isempty(x) || isa(x, 'function_handle'));
    parse(ip, varargin{:});
    opt = ip.Results;

    if ischar(cfgIn) || isstring(cfgIn)
        cfg = flow.load_cfg(cfgIn);
    elseif isstruct(cfgIn)
        cfg = cfgIn;
    else
        error('source:build_pipeline:BadConfig', 'cfgOrPath must be a struct or a JSON path.');
    end

    if isfield(cfg, 'steps')
        steps = cfg.steps;
    elseif isfield(cfg, 'spec') && isstruct(cfg.spec) && isfield(cfg.spec, 'steps')
        steps = cfg.spec.steps;
    else
        error('source:build_pipeline:MissingSteps', 'cfg.steps (or cfg.spec.steps) is required.');
    end

    for i = 1:numel(steps)
        if isfield(steps(i), 'args_ref') && ~isempty(steps(i).args_ref)
            ref = char(steps(i).args_ref);
            if ~isfield(cfg, ref)
                error('source:build_pipeline:ArgsRefMissing', 'cfg.%s not found.', ref);
            end
            if ~isfield(steps(i), 'args') || isempty(steps(i).args)
                steps(i).args = cfg.(ref);
            end
        end
        if ~isfield(steps(i), 'args') || isempty(steps(i).args)
            steps(i).args = struct();
        end
        steps(i).args = local_inject_defaults(steps(i).op, steps(i).args, cfg);
    end

    if isempty(opt.Registry)
        reg = init_registry();
    else
        reg = opt.Registry;
    end

    state = opt.State;
    state.cfg = cfg;

    pipe = flow.Pipeline(state, reg);
    if ~isempty(opt.WhenEvaluatorFn)
        pipe.setWhenEvaluator(opt.WhenEvaluatorFn);
    end
    pipe = pipe.add_steps(struct('steps', steps));
end

function args = local_inject_defaults(op, args, cfg)
    opName = lower(char(op));
    opsNeedLogfile = {'load_set','save_set','check_headmodel','source_reconstruct_epochs','source_parcellate','source_compute_erps','source_extract_window_feature','erp_compute_source_erps','erp_extract_source_feature','tf_compute_source','tf_extract_source_feature'};
    if (ismember(opName, opsNeedLogfile) || isfield(args, 'LogFile')) && ...
            (~isfield(args, 'LogFile') || isempty(args.LogFile))
        if isfield(cfg, 'LogFile') && ~isempty(cfg.LogFile)
            args.LogFile = cfg.LogFile;
        end
    end
end
