function nv = ctx_struct2nv(s)
%CTX_STRUCT2NV Convert struct to name-value cell array
    if isempty(s)
        nv = {};
        return;
    end
    fields = fieldnames(s);
    values = struct2cell(s);
    nv = cell(1, numel(fields) * 2);
    for i = 1:numel(fields)
        nv{2*i-1} = fields{i};
        nv{2*i} = values{i};
    end
end
