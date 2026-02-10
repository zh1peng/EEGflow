function [pipe, state, cfg] = build_pipeline(cfgIn, varargin)
%BUILD_PIPELINE Build a rest Pipeline from config (state-based).
%
% Usage:
%   [pipe, state, cfg] = rest.build_pipeline(cfgOrPath);
%   [pipe, state, cfg] = rest.build_pipeline(cfgOrPath, 'State', state, 'Registry', reg);
%
% Inputs:
%   cfgOrPath   config struct OR path to JSON (loaded via flow.load_cfg)
%
% Options:
%   'State'            : Initial state struct (default: struct())
%   'Registry'         : containers.Map registry (default: rest private registry)
%   'WhenEvaluatorFn'  : @(exprString, state) for string "when" (default: [])
%
% Output:
%   pipe   flow.Pipeline configured with steps
%   state  initial state used by pipeline (state.cfg populated)
%   cfg    resolved config used to build steps

    ip = inputParser;
    addParameter(ip, 'State', struct(), @isstruct);
    addParameter(ip, 'Registry', [], @(x) isempty(x) || isa(x, 'containers.Map'));
    addParameter(ip, 'WhenEvaluatorFn', [], @(x) isempty(x) || isa(x,'function_handle'));
    parse(ip, varargin{:});
    opt = ip.Results;

    % --- load cfg ---
    if ischar(cfgIn) || isstring(cfgIn)
        cfg = flow.load_cfg(cfgIn);
    elseif isstruct(cfgIn)
        cfg = cfgIn;
    else
        error('rest:build_pipeline:BadConfig', 'cfgOrPath must be a struct or a JSON path.');
    end

    % --- extract steps ---
    if isfield(cfg, 'steps')
        steps = cfg.steps;
    elseif isfield(cfg, 'spec') && isstruct(cfg.spec) && isfield(cfg.spec, 'steps')
        steps = cfg.spec.steps;
    else
        error('rest:build_pipeline:MissingSteps', 'cfg.steps (or cfg.spec.steps) is required.');
    end

    % --- resolve args_ref and fill defaults ---
    for i = 1:numel(steps)
        if isfield(steps(i), 'args_ref') && ~isempty(steps(i).args_ref)
            ref = char(steps(i).args_ref);
            if ~isfield(cfg, ref)
                error('rest:build_pipeline:ArgsRefMissing', 'cfg.%s not found.', ref);
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

    % --- state + registry ---
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
    ops_need_logfile = {'load_set','save_set','segment_rest','compute_all_features'};

    if (ismember(opName, ops_need_logfile) || isfield(args, 'LogFile')) ...
            && (~isfield(args, 'LogFile') || isempty(args.LogFile))
        if isfield(cfg, 'LogFile') && ~isempty(cfg.LogFile)
            args.LogFile = cfg.LogFile;
        end
    end
end
