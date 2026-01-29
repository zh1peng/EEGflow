function state = erp_define_group(state, args, meta)
%ERP_DEFINE_GROUP Define an ERP group (wrapper for define_group).
    if nargin < 2, args = struct(); end
    if nargin < 3, meta = struct(); end
    state = analysis.define_group(state, args, meta);
end
