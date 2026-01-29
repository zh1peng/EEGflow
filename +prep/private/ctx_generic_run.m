function context = ctx_generic_run(context, args, meta, fHandle, opName, defaults, aliases, varargin)
%CTX_GENERIC_RUN Generic engine for simple prep_ctx wrappers
%
% Usage:
%   context = ctx_generic_run(context, args, meta, ...
%       @prep.func, 'op_name', default_struct, alias_cell_array)

    if nargin < 2 || isempty(args), args = struct(); end
    if nargin < 3 || isempty(meta), meta = struct(); end
    if nargin < 6 || isempty(defaults), defaults = struct(); end
    if nargin < 7, aliases = {}; end

    % --- Options ---
    ip = inputParser;
    addParameter(ip, 'RequireEEG', true, @(x) islogical(x) && isscalar(x));
    addParameter(ip, 'PreFn', [], @(f) isempty(f) || isa(f, 'function_handle'));
    addParameter(ip, 'ContextCheckFn', [], @(f) isempty(f) || isa(f, 'function_handle'));
    addParameter(ip, 'PostFn', [], @(f) isempty(f) || isa(f, 'function_handle'));
    parse(ip, varargin{:});
    opt = ip.Results;

    % --- 1. Resolve Params ---
    cfg = ctx_get_config(context, opName);
    if ~isempty(cfg), defaults = ctx_merge(defaults, cfg); end
    params = ctx_merge(defaults, args);

    % Apply aliases (Cell array: {'alias', 'real'})
    for i = 1:size(aliases, 1)
        params = ctx_alias(params, aliases{i,1}, aliases{i,2});
    end
    % Ensure alias targets exist even if absent in defaults/args
    for i = 1:size(aliases, 1)
        tgt = aliases{i,2};
        if ~isfield(params, tgt)
            params.(tgt) = [];
        end
    end
    if ~isempty(opt.PreFn)
        params = opt.PreFn(params);
    end
    if ~isempty(opt.ContextCheckFn)
        [context, params] = opt.ContextCheckFn(context, params);
    end

    % --- 2. Validate-only short-circuit ---
    if isfield(meta, 'validate_only') && meta.validate_only
        return;
    end

    % --- 3. Validate data-dependent inputs ---
    if opt.RequireEEG
        if ~isfield(context, 'EEG') || isempty(context.EEG)
            error('PrepCtx:NoData', 'EEG is empty. Load data before running %s.', opName);
        end
    end

    % --- 4. Execution ---
    try
        nvPairs = ctx_struct2nv(params);
        [EEG, out] = ctx_call_prep(fHandle, context.EEG, nvPairs{:});
        context.EEG = EEG;
        if ~isempty(opt.PostFn)
            [context, out] = opt.PostFn(context, params, out);
        end
        context = ctx_update_history(context, opName, params, 'success', out);
    catch ME
        error('PrepCtx:Failed', '%s failed: %s', opName, ME.message);
    end
end
