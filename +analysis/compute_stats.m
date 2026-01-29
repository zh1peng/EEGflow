function ctx = compute_stats(ctx, args, ~)
    % Args: contrast, roi, alpha, mcc, time_window
    if nargin < 2, args = struct(); end
    % defaults
    if ~isfield(args, 'alpha'), args.alpha = 0.05; end
    if ~isfield(args, 'mcc'), args.mcc = 'none'; end
    if ~isfield(args, 'time_window'), args.time_window = []; end
    
    ctx_check(ctx, 'GA');
    cname = args.contrast;
    if ~isfield(ctx.Results.Contrasts, cname), error('Contrast %s not found.', cname); end
    
    fprintf('Computing stats for %s...\n', cname);
    
    def = ctx.Results.Contrasts.(cname);
    [pos_s, pos_c] = deal(def.positive_term{:});
    [neg_s, neg_c] = deal(def.negative_term{:});
    
    [pos_d, pos_found] = ctx_collect_erps(ctx, ctx.Selection.Groups.(pos_s), pos_c);
    [neg_d, neg_found] = ctx_collect_erps(ctx, ctx.Selection.Groups.(neg_s), neg_c);
    
    dim = 3;
    if isfield(args, 'roi') && ~isempty(args.roi)
        idxs = ctx_get_indices(ctx, args.roi);
        pos_d = squeeze(mean(pos_d(idxs,:,:), 1));
        neg_d = squeeze(mean(neg_d(idxs,:,:), 1));
        dim = 2;
    end
    
    % T-Test logic (Simplified for brevity, similar to original)
    is_paired = isequal(ctx.Selection.Groups.(pos_s), ctx.Selection.Groups.(neg_s)) && strcmp(pos_s, neg_s);
    
    if is_paired
        [~, ia, ib] = intersect(pos_found, neg_found, 'stable');
        if dim==3, d1=pos_d(:,:,ia); d2=neg_d(:,:,ib); else, d1=pos_d(:,ia); d2=neg_d(:,ib); end
        [~, p, ~, stats] = ttest(d1-d2, 0, 'dim', dim);
    else
        [~, p, ~, stats] = ttest2(pos_d, neg_d, 'dim', dim);
    end
    
    % Store Results
    ctx.Results.Contrasts.(cname).Stats.p = p;
    ctx.Results.Contrasts.(cname).Stats.t = stats.tstat;
    ctx.Results.Contrasts.(cname).Stats.h = p < args.alpha; % Add MCC logic here if needed
    ctx.Results.Contrasts.(cname).Stats.roi = args.roi;
    
    fprintf('Stats done.\n');
end