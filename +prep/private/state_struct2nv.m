function nv = state_struct2nv(s)
%STATE_STRUCT2NV Convert struct to name-value cell array.
    if isempty(s)
        nv = {};
        return;
    end
    f = fieldnames(s);
    nv = cell(1, 2 * numel(f));
    for i = 1:numel(f)
        nv{2*i-1} = f{i};
        nv{2*i} = s.(f{i});
    end
end
