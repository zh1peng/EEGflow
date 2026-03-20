function state = erp_plot_subject_contrast(state, args, meta)
%ERP_PLOT_SUBJECT_CONTRAST Plot subject-level ERP difference wave with optional stats shading.
% Args:
%   contrast (char), target (char), show_sig (bool), sig_alpha, sig_color,
%   time_window (1x2, display only), smoothing_factor, show_error(se|sd|std|none), ErrorAlpha, ErrorColor

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

    state_check(state, 'SubjectContrasts');
    ver = analysis.get_version();
    cname = args.contrast;
    if ~isfield(state.Results.SubjectContrasts, cname)
        error('Subject contrast "%s" not found. Run erp_compute_subject_contrast first.', cname);
    end
    C = state.Results.SubjectContrasts.(cname);
    if ~isfield(C, 'erps') || isempty(C.erps)
        error('Subject contrast "%s" has no ERP data.', cname);
    end

    if isempty(args.target)
        error('target is required for erp_plot_subject_contrast.');
    end
    [chan_idx, plot_title] = state_get_indices(state, args.target);
    times = state.Dataset.times;

    stack = C.erps;
    chan_avg = squeeze(mean(stack(chan_idx, :, :), 1)); % [time x subj] or [time x 1]
    if isvector(chan_avg)
        wave = reshape(chan_avg, 1, []);
    else
        wave = mean(chan_avg, 2)';
    end
    if args.smoothing_factor > 1
        wave = smoothdata(wave, 'movmean', args.smoothing_factor);
    end

    figure;
    ax = gca;
    hold(ax, 'on');
    h_wave = plot(ax, times, wave, 'LineWidth', 2, 'Color', [0.1 0.1 0.1]);

    if ~strcmpi(args.show_error, 'none')
        err_data = state_calc_error(args.show_error, stack, chan_idx);
        if ~isempty(err_data)
            if args.smoothing_factor > 1
                err_data = smoothdata(err_data, 'movmean', args.smoothing_factor);
            end
            err_color = args.ErrorColor;
            if isempty(err_color)
                err_color = [0.2 0.2 0.2];
            end
            fill(ax, [times, fliplr(times)], [wave - err_data, fliplr(wave + err_data)], ...
                err_color, 'FaceAlpha', args.ErrorAlpha, 'EdgeColor', 'none', 'HandleVisibility', 'off');
        end
    end

    if args.show_sig && isfield(C, 'Stats') && isfield(C.Stats, 'h')
        validate_stats_target(C.Stats, args.target, args.time_window, times);
        sig_mask = C.Stats.h;
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
    title(ax, sprintf('Subject Contrast: %s (%s) | EEGflow v%s', cname, plot_title, ver), 'Interpreter', 'none');
    legend(ax, h_wave, sprintf('%s (N=%d)', cname, C.n), 'Location', 'best', 'Interpreter', 'none');
    hline = line(ax, ax.XLim, [0 0], 'Color', 'k', 'LineStyle', '--');
    set(get(get(hline,'Annotation'),'LegendInformation'), 'IconDisplayStyle', 'off');
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
