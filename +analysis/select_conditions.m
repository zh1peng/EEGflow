function ctx = select_conditions(ctx, args, ~)
    % Args: conditions (cell)
    ctx_check(ctx);
    conds = args.conditions;
    miss = setdiff(conds, ctx.Dataset.conditions);
    if ~isempty(miss), warning('Missing conditions ignored: %s', strjoin(miss, ', ')); end
    ctx.Selection.Conditions = intersect(conds, ctx.Dataset.conditions);
    fprintf('Selected %d conditions.\n', numel(ctx.Selection.Conditions));
end