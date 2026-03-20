function state = erp_plot_contrast(state, args, meta)
%ERP_PLOT_CONTRAST Plot an ERP contrast with optional significance shading.
% Args:
%   contrast (char), target (char), show_sig (bool), sig_alpha, sig_color,
%   time_window (1x2, display only), smoothing_factor, show_error(se|sd|std|none), ErrorAlpha, ErrorColor,
%   show_diff (bool)

    if nargin < 2, args = struct(); end
    if nargin >= 3 && isfield(meta, 'validate_only') && meta.validate_only
        return;
    end
    if ~isfield(args, 'contrast'), error('contrast is required.'); end
    if ~isfield(args, 'target'), args.target = ''; end
    if ~isfield(args, 'show_sig'), args.show_sig = true; end
    if ~isfield(args, 'sig_alpha'), args.sig_alpha = 0.6; end
    if ~isfield(args, 'sig_color'), args.sig_color = [0.8 0.8 0.8]; end
    if ~isfield(args, 'time_window'), args.time_window = []; end
    if ~isfield(args, 'smoothing_factor'), args.smoothing_factor = 1; end
    if ~isfield(args, 'show_error'), args.show_error = 'se'; end
    if ~isfield(args, 'ErrorAlpha'), args.ErrorAlpha = 0.6; end
    if ~isfield(args, 'ErrorColor'), args.ErrorColor = []; end
    if ~isfield(args, 'show_diff'), args.show_diff = false; end

    state_check(state, 'GA');
    ver = analysis.get_version();
    if ~isfield(state.Results, 'Contrasts') || ~isfield(state.Results.Contrasts, args.contrast)
        error('Contrast "%s" not found. Run erp_define_contrast first.', args.contrast);
    end
    contrast_def = state.Results.Contrasts.(args.contrast);

    if isempty(args.target)
        error('target is required for erp_plot_contrast.');
    end
    [chan_idx, plot_title] = state_get_indices(state, args.target);
    times = state.Dataset.times;

    pos_term = contrast_def.positive_term;
    neg_term = contrast_def.negative_term;
    pos_group = pos_term{1};
    neg_group = neg_term{1};
    pos_cond = pos_term{2};
    neg_cond = neg_term{2};

    pos_ga = state.Results.GA.(pos_group).(pos_cond).erp;
    neg_ga = state.Results.GA.(neg_group).(neg_cond).erp;
    pos_wave = mean(pos_ga(chan_idx, :), 1);
    neg_wave = mean(neg_ga(chan_idx, :), 1);
    diff_wave = pos_wave - neg_wave;

    if args.smoothing_factor > 1
        pos_wave = smoothdata(pos_wave, 'movmean', args.smoothing_factor);
        neg_wave = smoothdata(neg_wave, 'movmean', args.smoothing_factor);
        diff_wave = smoothdata(diff_wave, 'movmean', args.smoothing_factor);
    end

    figure;
    ax = gca;
    hold(ax, 'on');
    h_pos = plot(ax, times, pos_wave, 'LineWidth', 2, 'Color', [0 0.5 0]);
    h_neg = plot(ax, times, neg_wave, 'LineWidth', 2, 'Color', [0.7 0 0]);
    if args.show_diff
        h_diff = plot(ax, times, diff_wave, 'LineWidth', 2, 'LineStyle', '-.', 'Color', [0 0 0]);
    end

    if ~strcmpi(args.show_error, 'none')
        pos_subs = state.Selection.Groups.(pos_group);
        neg_subs = state.Selection.Groups.(neg_group);
        [pos_stack, ~] = state_collect_erps(state, pos_subs, pos_cond);
        [neg_stack, ~] = state_collect_erps(state, neg_subs, neg_cond);
        pos_err = state_calc_error(args.show_error, pos_stack, chan_idx);
        neg_err = state_calc_error(args.show_error, neg_stack, chan_idx);

        if ~isempty(pos_err)
            fill(ax, [times, fliplr(times)], [pos_wave - pos_err, fliplr(pos_wave + pos_err)], ...
                pick_err_color(args.ErrorColor, h_pos.Color), 'FaceAlpha', args.ErrorAlpha, ...
                'EdgeColor', 'none', 'HandleVisibility', 'off');
        end
        if ~isempty(neg_err)
            fill(ax, [times, fliplr(times)], [neg_wave - neg_err, fliplr(neg_wave + neg_err)], ...
                pick_err_color(args.ErrorColor, h_neg.Color), 'FaceAlpha', args.ErrorAlpha, ...
                'EdgeColor', 'none', 'HandleVisibility', 'off');
        end
    end

    if args.show_sig && isfield(contrast_def, 'Stats') && isfield(contrast_def.Stats, 'h')
        validate_stats_target(contrast_def.Stats, args.target, args.time_window, times);
        sig_mask = contrast_def.Stats.h;
        if size(sig_mask, 1) > 1
            sig_mask = any(sig_mask(chan_idx, :), 1);
        end
        wins = state_get_sig_windows(sig_mask, times);
        if ~isempty(wins)
            yl = ylim(ax);
            for i = 1:size(wins, 1)
                patch(ax, ...
                    [wins(i, 1), wins(i, 2), wins(i, 2), wins(i, 1)], ...
                    [yl(1), yl(1), yl(2), yl(2)], ...
                    args.sig_color, ...
                    'FaceAlpha', args.sig_alpha, ...
                    'EdgeColor', 'none', ...
                    'HandleVisibility', 'off');
            end
        end
    end

    if ~isempty(args.time_window)
        xlim(ax, args.time_window);
    end
    grid(ax, 'on');
    box(ax, 'on');
    set(ax, 'YDir', 'reverse');
    xlabel(ax, 'Time (ms)', 'Interpreter', 'none');
    ylabel(ax, 'Amplitude (uV)', 'Interpreter', 'none');
    title(ax, sprintf('%s (%s) | EEGflow v%s', args.contrast, plot_title, ver), 'Interpreter', 'none');

    legend_handles = [h_pos, h_neg];
    legend_labels = {sprintf('%s:%s', pos_group, pos_cond), sprintf('%s:%s', neg_group, neg_cond)};
    if args.show_diff
        legend_handles(end+1) = h_diff; %#ok<AGROW>
        legend_labels{end+1} = args.contrast; %#ok<AGROW>
    end
    legend(ax, legend_handles, legend_labels, 'Location', 'best', 'Interpreter', 'none');
    hline = line(ax, ax.XLim, [0 0], 'Color', 'k', 'LineStyle', '--');
    set(get(get(hline,'Annotation'),'LegendInformation'), 'IconDisplayStyle', 'off');
end

function c = pick_err_color(user_color, fallback)
    if isempty(user_color)
        c = fallback;
    else
        c = user_color;
    end
end

function validate_stats_target(stats, target, plot_tw, times)
    if isfield(stats, 'roi') && ~isempty(stats.roi) && ~strcmp(stats.roi, target)
        error('Stats were computed on ROI "%s" but plot target is "%s".', stats.roi, target);
    end

    if ~isfield(stats, 'time_window') || isempty(stats.time_window)
        return;
    end
    stats_tw = stats.time_window;
    if isempty(plot_tw)
        plot_tw = [times(1), times(end)];
    end
    if plot_tw(2) < stats_tw(1) || plot_tw(1) > stats_tw(2)
        warning('Plot time window [%g %g] ms does not overlap stats window [%g %g] ms.', ...
            plot_tw(1), plot_tw(2), stats_tw(1), stats_tw(2));
    end
end
