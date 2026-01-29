function state = erp_compute_erps(state, args, meta)
%ERP_COMPUTE_ERPS Compute subject-level ERPs (wrapper for compute_erps).
    if nargin < 2, args = struct(); end
    if nargin < 3, meta = struct(); end
    state = analysis.compute_erps(state, args, meta);
end
