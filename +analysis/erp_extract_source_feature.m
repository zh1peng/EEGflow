function state = erp_extract_source_feature(state, args, meta)
%ERP_EXTRACT_SOURCE_FEATURE Extract source ERP time-window features.

    if nargin < 2 || isempty(args), args = struct(); end
    if nargin < 3, meta = struct(); end

    state = source.extract_window_feature(state, args, meta);
    if ~isfield(state, 'erp_source') || ~isstruct(state.erp_source)
        state.erp_source = struct();
    end
    state.erp_source.features = state.source.features;
end
