function state = check_headmodel(state, args, meta)
%CHECK_HEADMODEL Compatibility wrapper for source.check_headmodel.
%
% Prefer source.check_headmodel for new workflows. This wrapper preserves the
% historical rest.check_headmodel API and mirrors state.source.geometry into
% state.rest.headmodel for older rest scripts.

    if nargin < 1 || isempty(state), state = struct(); end
    if nargin < 2 || isempty(args),  args = struct();  end
    if nargin < 3 || isempty(meta),  meta = struct();  end

    state = source.check_headmodel(state, args, meta);

    if isfield(state, 'source') && isstruct(state.source) && ...
            isfield(state.source, 'geometry') && isstruct(state.source.geometry)
        if ~isfield(state, 'rest') || ~isstruct(state.rest)
            state.rest = struct();
        end
        state.rest.headmodel = state.source.geometry;
    end
end
