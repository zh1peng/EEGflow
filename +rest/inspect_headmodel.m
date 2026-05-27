function [qc, geom, state] = inspect_headmodel(eegOrSetFile, varargin)
%INSPECT_HEADMODEL Compatibility wrapper for source.inspect_headmodel.
%
% Prefer source.inspect_headmodel for new workflows.

    [qc, geom, state] = source.inspect_headmodel(eegOrSetFile, varargin{:});
    if isfield(state, 'source') && isstruct(state.source) && ...
            isfield(state.source, 'geometry') && isstruct(state.source.geometry)
        if ~isfield(state, 'rest') || ~isstruct(state.rest)
            state.rest = struct();
        end
        state.rest.headmodel = state.source.geometry;
    end
end
