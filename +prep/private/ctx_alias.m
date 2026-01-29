function p = ctx_alias(p, from, to)
%CTX_ALIAS Assign alias field if target missing
    if isfield(p, from) && ~isfield(p, to)
        p.(to) = p.(from);
    end
end
