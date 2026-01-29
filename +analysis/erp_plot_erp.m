function state = erp_plot_erp(state, args, meta)
%ERP_PLOT_ERP Plot GA ERP for a target (wrapper).
    if nargin < 2, args = struct(); end
    if nargin < 3, meta = struct(); end
    state = analysis.plot_erp(state, args, meta);
end
