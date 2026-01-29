function state = erp_compute_ga(state, args, meta)
%ERP_COMPUTE_GA Compute grand averages (wrapper for compute_ga).
    if nargin < 2, args = struct(); end
    if nargin < 3, meta = struct(); end
    state = analysis.compute_ga(state, args, meta);
end
