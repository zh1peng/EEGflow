function ctx = define_group(ctx, args, ~)
    % Args: name (char), subjects (cell)
    ctx_check(ctx);
    name = args.name; 
    subs = args.subjects;
    
    miss = setdiff(subs, ctx.Dataset.subjects);
    if ~isempty(miss), warning('Missing subjects ignored: %s', strjoin(miss, ', ')); end
    
    ctx.Selection.Groups.(name) = intersect(subs, ctx.Dataset.subjects);
    fprintf('Group %s defined (%d subs).\n', name, numel(ctx.Selection.Groups.(name)));
end