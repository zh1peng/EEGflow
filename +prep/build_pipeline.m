function [pipe, state, cfg] = build_pipeline(cfgIn, varargin)
%BUILD_PIPELINE Build a prep Pipeline from config (state-based).
%
% Usage:
%   [pipe, state, cfg] = prep.build_pipeline(cfgOrPath);
%   [pipe, state, cfg] = prep.build_pipeline(cfgOrPath, 'State', state, 'Registry', reg);
%   [pipe, state, cfg] = prep.build_pipeline(cfgOrPath, 'ConfigureIO', true, ...
%       'ConfigureIOArgs', {'Suffix','_cleaned'});
%
% Inputs:
%   cfgOrPath   config struct OR path to JSON (loaded via flow.load_cfg)
%
% Options:
%   'State'            : Initial state struct (default: struct())
%   'Registry'         : containers.Map registry (default: flow.Registry())
%   'ConfigureIO'      : Apply prep.setup_io to cfg (default: true)
%   'ConfigureIOArgs'  : NV args passed to prep.setup_io (default: {})
%   'WhenEvaluatorFn'  : @(exprString, state) for string "when" (default: [])
%
% Output:
%   pipe   flow.Pipeline configured with steps
%   state  initial state used by pipeline (state.cfg populated)
%   cfg    resolved config used to build steps

    ip = inputParser;
    addParameter(ip, 'State', struct(), @isstruct);
    addParameter(ip, 'Registry', [], @(x) isempty(x) || isa(x, 'containers.Map'));
    addParameter(ip, 'ConfigureIO', true, @(x) islogical(x) && isscalar(x));
    addParameter(ip, 'ConfigureIOArgs', {}, @(x) iscell(x) || isstruct(x));
    addParameter(ip, 'WhenEvaluatorFn', [], @(x) isempty(x) || isa(x,'function_handle'));
    parse(ip, varargin{:});
    opt = ip.Results;

    % --- load cfg ---
    if ischar(cfgIn) || isstring(cfgIn)
        cfg = flow.load_cfg(cfgIn);
    elseif isstruct(cfgIn)
        cfg = cfgIn;
    else
        error('prep:build_pipeline:BadConfig', 'cfgOrPath must be a struct or a JSON path.');
    end

    % --- optional IO configuration ---
    if opt.ConfigureIO && (isfield(cfg,'Input') || isfield(cfg,'Output'))
        ioArgs = opt.ConfigureIOArgs;
        if isstruct(ioArgs)
            ioArgs = local_struct2nv(ioArgs);
        end
        cfg = prep.setup_io(cfg, ioArgs{:});
    end

    % --- extract steps ---
    if isfield(cfg, 'steps')
        steps = cfg.steps;
    elseif isfield(cfg, 'spec') && isstruct(cfg.spec) && isfield(cfg.spec, 'steps')
        steps = cfg.spec.steps;
    else
        error('prep:build_pipeline:MissingSteps', 'cfg.steps (or cfg.spec.steps) is required.');
    end

    % --- resolve args_ref and fill defaults ---
    for i = 1:numel(steps)
        if isfield(steps(i), 'args_ref') && ~isempty(steps(i).args_ref)
            ref = char(steps(i).args_ref);
            if ~isfield(cfg, ref)
                error('prep:build_pipeline:ArgsRefMissing', 'cfg.%s not found.', ref);
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
        reg = flow.Registry();
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
    ops_need_logfile = { ...
        'load_set','load_mff','save_set','downsample','filter','remove_powerline', ...
        'crop_by_markers','remove_bad_channels','remove_bad_ICs','remove_channels', ...
        'reref','correct_baseline','interpolate','interpolate_bad_channels_epoch', ...
        'remove_bad_epoch','select_channels','segment_rest','segment_task','insert_relative_markers', ...
        'edit_chantype'};
    ops_need_logpath = {'remove_bad_channels','remove_bad_ICs'};

    % LogFile default (only when op expects it or args already has the field)
    if (ismember(opName, ops_need_logfile) || isfield(args, 'LogFile')) ...
            && (~isfield(args, 'LogFile') || isempty(args.LogFile))
        if isfield(cfg, 'LogFile') && ~isempty(cfg.LogFile)
            args.LogFile = cfg.LogFile;
        end
    end

    % LogPath default (only when op expects it or args already has the field)
    if (ismember(opName, ops_need_logpath) || isfield(args, 'LogPath')) ...
            && (~isfield(args, 'LogPath') || isempty(args.LogPath))
        if isfield(cfg, 'Output') && isfield(cfg.Output, 'filepath') && ~isempty(cfg.Output.filepath)
            args.LogPath = cfg.Output.filepath;
        end
    end

    % filename/filepath are populated by prep.setup_io (do not inject here)
end

function nv = local_struct2nv(s)
    f = fieldnames(s);
    nv = cell(1, numel(f)*2);
    for k = 1:numel(f)
        nv{2*k-1} = f{k};
        nv{2*k}   = s.(f{k});
    end
end
