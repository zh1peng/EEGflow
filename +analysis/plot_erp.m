function ctx = plot_erp(ctx, args, meta)
    % Args: target, smoothing, show_error, etc.
    if nargin < 2, args = struct(); end
    if ~isfield(args, 'target'), error('Target required'); end
    if ~isfield(args, 'show_error'), args.show_error = 'se'; end
    
    % Skip plotting in Agent "validate" or "dry_run" unless explicitly saving
    if nargin >= 3 && isfield(meta, 'dry_run') && meta.dry_run
        fprintf('[DryRun] Would plot ERP for %s\n', args.target);
        return;
    end
    
    ctx_check(ctx, 'GA');
    [idxs, title_str] = ctx_get_indices(ctx, args.target);
    times = ctx.Dataset.times;
    
    figure; hold on;
    groups = fieldnames(ctx.Results.GA);
    colors = lines(numel(groups) * numel(ctx.Selection.Conditions));
    ci = 1;
    
    for g = 1:numel(groups)
        gn = groups{g};
        conds = fieldnames(ctx.Results.GA.(gn));
        for c = 1:numel(conds)
            cn = conds{c};
            ga = ctx.Results.GA.(gn).(cn).erp;
            wave = mean(ga(idxs, :), 1);
            
            h = plot(times, wave, 'Color', colors(ci,:), 'LineWidth', 2);
            
            % Error bands
            if ~strcmp(args.show_error, 'none')
                subs = ctx.Selection.Groups.(gn);
                [stack, ~] = ctx_collect_erps(ctx, subs, cn);
                err = ctx_calc_error(args.show_error, stack, idxs);
                if ~isempty(err)
                     fill([times, fliplr(times)], [wave-err, fliplr(wave+err)], ...
                         colors(ci,:), 'FaceAlpha', 0.3, 'EdgeColor', 'none');
                end
            end
            ci = ci + 1;
        end
    end
    title(title_str); grid on;
end