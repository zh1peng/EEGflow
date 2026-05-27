function state = erp_compute_source_erps(state, args, meta)
%ERP_COMPUTE_SOURCE_ERPS Compute parcel/source ERP waveforms.

    if nargin < 2 || isempty(args), args = struct(); end
    if nargin < 3, meta = struct(); end

    state = source.compute_erps(state, args, meta);
    if ~isfield(state, 'erp_source') || ~isstruct(state.erp_source)
        state.erp_source = struct();
    end
    state.erp_source.erps = state.source.erp;
end
