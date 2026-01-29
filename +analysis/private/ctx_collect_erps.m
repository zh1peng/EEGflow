function [stack, found] = ctx_collect_erps(ctx, subs, cond)
    stack_cell = {};
    found = {};
    for i = 1:numel(subs)
        sid = subs{i};
        sfield = sid;
        if isfield(ctx.Results.ERPs, sfield) && isfield(ctx.Results.ERPs.(sfield), cond)
            stack_cell{end+1} = ctx.Results.ERPs.(sfield).(cond); %#ok<AGROW>
            found{end+1} = sid; %#ok<AGROW>
        end
    end
    if ~isempty(stack_cell), stack = cat(3, stack_cell{:}); else, stack = []; end
end
