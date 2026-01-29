function cfg = ctx_get_config(context, opName)
%CTX_GET_CONFIG Case-insensitive lookup in context.cfg
    cfg = [];
    if ~isfield(context, 'cfg') || ~isstruct(context.cfg)
        return;
    end
    fn = fieldnames(context.cfg);
    for i = 1:numel(fn)
        if strcmpi(fn{i}, opName)
            cfg = context.cfg.(fn{i});
            return;
        end
    end
end
