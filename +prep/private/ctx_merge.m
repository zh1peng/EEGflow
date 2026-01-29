function p = ctx_merge(base, cover)
%CTX_MERGE Shallow merge: fields in cover override base
    p = base;
    if isempty(p)
        p = struct();
    end
    if isempty(cover) || ~isstruct(cover), return; end
    f = fieldnames(cover);
    for i = 1:numel(f)
        p.(f{i}) = cover.(f{i});
    end
end
