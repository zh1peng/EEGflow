function state = erp_compute_stats(state, args, meta)
%ERP_COMPUTE_STATS Compute ERP stats for a contrast (wrapper).
    if nargin < 2, args = struct(); end
    if nargin < 3, meta = struct(); end
    state = analysis.compute_stats(state, args, meta);
end
