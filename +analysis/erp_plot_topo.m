function state = erp_plot_topo(state, args, meta)
%ERP_PLOT_TOPO Plot topographies for a named time window.
% Args: time_window (char)

    if nargin < 2, args = struct(); end
    if ~isfield(args, 'time_window') || isempty(args.time_window)
        error('time_window is required.');
    end
    if nargin >= 3 && isfield(meta, 'validate_only') && meta.validate_only
        return;
    end

    state_check(state, 'GA');
    if ~isfield(state.Selection, 'TimeWindows') || ~isfield(state.Selection.TimeWindows, args.time_window)
        error('Time window "%s" not found. Define it first.', args.time_window);
    end
    if ~exist('topoplot', 'file')
        warning('topoplot not found on MATLAB path. Falling back to bar plot.');
    end

    time_range = state.Selection.TimeWindows.(args.time_window);
    times = state.Dataset.times;
    time_idx = times >= time_range(1) & times <= time_range(2);

    group_names = fieldnames(state.Results.GA);
    num_groups = numel(group_names);
    condition_names = fieldnames(state.Results.GA.(group_names{1}));
    num_conditions = numel(condition_names);

    figure('Position', [100, 100, 250 * num_conditions, 300 * num_groups]);
    plot_idx = 1;
    all_clim = [];

    for g = 1:num_groups
        group_name = group_names{g};
        condition_names = fieldnames(state.Results.GA.(group_name));
        for c = 1:numel(condition_names)
            condition_name = condition_names{c};
            subplot(num_groups, num_conditions, plot_idx);
            plot_idx = plot_idx + 1;

            ga = state.Results.GA.(group_name).(condition_name).erp;
            topo_vals = mean(ga(:, time_idx), 2);
            if exist('topoplot', 'file')
                topoplot(topo_vals, state.Dataset.chanlocs, 'maplimits','absmax');
                c = caxis;
                all_clim = [all_clim; c]; %#ok<AGROW>
            else
                bar(topo_vals);
                set(gca,'XTick',1:numel(topo_vals),'XTickLabel',{state.Dataset.chanlocs.labels},'XTickLabelRotation',45);
                ylabel('Mean amplitude (uV)');
            end
            title(sprintf('%s | %s', strrep(group_name,'_',' '), strrep(condition_name,'_',' ')));
        end
    end

    if exist('topoplot', 'file') && ~isempty(all_clim)
        clim = [min(all_clim(:,1)) max(all_clim(:,2))];
        for ax = findall(gcf, 'Type', 'axes')'
            caxis(ax, clim);
        end
        colorbar('Position', [0.92 0.1 0.02 0.8]);
    end
end
