function state = plot_erp(state, args, meta)
    % Args: target, smoothing_factor, show_error, ErrorAlpha, ErrorColor
    if nargin < 2, args = struct(); end
    if ~isfield(args, 'target'), error('Target required'); end
    if ~isfield(args, 'smoothing_factor'), args.smoothing_factor = 1; end
    if ~isfield(args, 'show_error'), args.show_error = 'se'; end
    if ~isfield(args, 'ErrorAlpha'), args.ErrorAlpha = 0.6; end
    if ~isfield(args, 'ErrorColor'), args.ErrorColor = []; end

    if nargin >= 3 && isfield(meta, 'validate_only') && meta.validate_only
        fprintf('[ValidateOnly] Would plot ERP for %s\n', args.target);
        return;
    end

    state_check(state, 'GA');
    [idxs, title_str] = state_get_indices(state, args.target);
    times = state.Dataset.times;
    group_names = fieldnames(state.Results.GA);
    colors = get(groot, 'defaultAxesColorOrder');

    for g = 1:numel(group_names)
        group_name = group_names{g};
        figure;
        hold on;
        condition_names = fieldnames(state.Results.GA.(group_name));
        plot_handles = [];
        legend_labels = {};
        for c = 1:numel(condition_names)
            condition_name = condition_names{c};
            ga = state.Results.GA.(group_name).(condition_name).erp;
            n = state.Results.GA.(group_name).(condition_name).n;
            waveform = mean(ga(idxs, :), 1);
            if args.smoothing_factor > 1
                waveform = smoothdata(waveform, 'movmean', args.smoothing_factor);
            end

            plot_color = colors(mod(c-1, size(colors, 1)) + 1, :);
            h = plot(times, waveform, 'LineWidth', 2, 'Color', plot_color, 'LineStyle', '-');

            if ~strcmpi(args.show_error, 'none')
                subject_ids = state.Selection.Groups.(group_name);
                [erp_stack, ~] = state_collect_erps(state, subject_ids, condition_name);
                err_data = state_calc_error(args.show_error, erp_stack, idxs);
                final_error_color = args.ErrorColor;
                if isempty(final_error_color)
                    final_error_color = plot_color;
                end
                if ~isempty(err_data)
                    fill([times, fliplr(times)], [waveform-err_data, fliplr(waveform+err_data)], ...
                        final_error_color, 'FaceAlpha', args.ErrorAlpha, 'EdgeColor', 'none', 'HandleVisibility', 'off');
                end
            end

            plot_handles(end+1) = h; %#ok<AGROW>
            legend_labels{end+1} = sprintf('%s (N=%d)', strrep(condition_name, '_', ' '), n); %#ok<AGROW>
        end
        hold off;
        set(gca, 'YDir', 'reverse');
        grid on; box on;
        xlabel('Time (ms)');
        ylabel('Amplitude (uV)');
        title(strrep(sprintf('ERP for %s (Group: %s)', title_str, group_name), '_', ' '));
        legend(plot_handles, legend_labels, 'Location', 'best');
        ax = gca;
        hline = line(ax.XLim, [0 0], 'Color', 'k', 'LineStyle', '--');
        set(get(get(hline, 'Annotation'), 'LegendInformation'), 'IconDisplayStyle', 'off');
    end
end
