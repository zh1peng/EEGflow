function out = state_merge(base, cover)
%STATE_MERGE Shallow merge: fields in cover override base.
    out = base;
    if isempty(out)
        out = struct();
    end
    if isempty(cover) || ~isstruct(cover)
        return;
    end
    f = fieldnames(cover);
    for i = 1:numel(f)
        out.(f{i}) = cover.(f{i});
    end
end
