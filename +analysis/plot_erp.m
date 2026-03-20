function state = plot_erp(state, args, meta)
%PLOT_ERP Legacy compatibility alias for analysis.erp_plot_erp.
    if nargin < 2, args = struct(); end
    if nargin < 3, meta = struct(); end
    state = analysis.erp_plot_erp(state, args, meta);
end
