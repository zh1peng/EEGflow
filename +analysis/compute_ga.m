function ctx = compute_ga(ctx, ~, ~)
    ctx_check(ctx, 'ERPs');
    groups = fieldnames(ctx.Selection.Groups);
    fprintf('Computing GA...\n');
    
    for g = 1:numel(groups)
        gn = groups{g};
        subs = ctx.Selection.Groups.(gn);
        for c = 1:numel(ctx.Selection.Conditions)
            cn = ctx.Selection.Conditions{c};
            [stack, ~] = ctx_collect_erps(ctx, subs, cn);
            if ~isempty(stack)
                ctx.Results.GA.(gn).(cn).erp = mean(stack, 3);
                ctx.Results.GA.(gn).(cn).n = size(stack, 3);
            end
        end
    end
end