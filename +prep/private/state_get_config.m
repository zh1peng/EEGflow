function cfg = state_get_config(state, opName)
%STATE_GET_CONFIG Case-insensitive lookup in state.cfg for op-specific config.
    cfg = struct();
    if nargin < 1 || isempty(state) || ~isstruct(state)
        return;
    end
    if ~isfield(state, 'cfg') || ~isstruct(state.cfg)
        return;
    end
    fn = fieldnames(state.cfg);
    for i = 1:numel(fn)
        if strcmpi(fn{i}, opName)
            cfg = state.cfg.(fn{i});
            return;
        end
    end
end
