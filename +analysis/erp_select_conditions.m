function state = erp_select_conditions(state, args, meta)
%ERP_SELECT_CONDITIONS Select conditions for ERP analysis (wrapper).
    if nargin < 2, args = struct(); end
    if nargin < 3, meta = struct(); end
    state = analysis.select_conditions(state, args, meta);
end
