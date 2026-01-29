classdef ERPanalysis
    % ERPANALYSIS  High-level ERP analysis workflow on an analysis.Dataset.
    %
    % DESIGN OVERVIEW
    %   ERPanalysis is a stateful, user-facing class that organizes an ERP
    %   workflow into three layers of state:
    %
    %   1) Dataset (immutable input)
    %      - An analysis.Dataset instance that provides:
    %          - trials by subject/condition (get_data)
    %          - time vector (times)
    %          - channel locations (chanlocs)
    %          - subject and condition lists
    %
    %   2) Selection (user choices)
    %      - Groups: subject lists keyed by group name
    %      - Conditions: list of condition names to analyze
    %      - ROIs: named channel sets
    %      - TimeWindows: named [start, end] intervals (ms)
    %
    %   3) Results (computed outputs)
    %      - ERPs: subject-level averages per condition
    %      - GA: grand averages per group and condition
    %      - Contrasts: condition/group contrasts + optional stats
    %      - Features: extracted metrics (e.g., mean/peak in windows)
    %
    % Typical usage follows this pipeline:
    %   1) Construct with an analysis.Dataset
    %   2) Define groups and select conditions
    %   3) Optionally define ROIs and time windows
    %   4) Compute ERPs and grand averages
    %   5) Plot ERPs/topos and compute contrasts/stats
    %   6) Extract features for ROI/time windows
    %
    % MINIMAL EXAMPLE
    %   ds = analysis.Dataset(Out); % Out from analysis.extract_epoch
    %   ea = ERPanalysis(ds);
    %   ea = ea.define_group('All', ds.get_subjects());
    %   ea = ea.select_conditions({'win_cue','loss_cue','neut_cue'});
    %   ea = ea.define_roi('Cz_ROI', {'FCz','FC2','Cz','C2','CP2'});
    %   ea = ea.define_time_window('P300', [300, 600]);
    %   ea = ea.compute_erps();
    %   ea = ea.compute_ga();
    %   ea.plot_erp('Cz_ROI');
    %   ea.plot_topo('time_window','P300');
    %
    % KEY METHODS (PUBLIC)
    %
    %   Setup / Selection
    %     - define_group(name, subject_ids)
    %     - select_conditions(condition_names)
    %     - define_roi(roi_name, channel_labels)
    %     - define_time_window(window_name, [start end])
    %
    %   Computation
    %     - compute_erps('averaging_method', 'mean|median|trimmed', ...)
    %     - compute_ga()
    %     - compute_contrast(name, positive_term, negative_term)
    %     - compute_stats('contrast', contrast_name, ...)
    %
    %   Plotting
    %     - plot_erp(target_name, ...)
    %     - plot_topo('time_window', window_name)
    %     - plot_contrast_erp(contrast_name, ...)
    %     - show_channels(...)
    %
    %   Features
    %     - extract_feature('roi', roi_name, 'time_window', window_name, ...)
    %
    % TERMS AND CONVENTIONS
    %   - A "term" in a contrast is {GroupName, ConditionName}.
    %   - target_name can be a single channel label or an ROI name.
    %   - Results are stored in struct fields using group/condition names.
    %
    % EXPECTED ORDER OF OPERATIONS
    %   - define_group and select_conditions must be called before compute_erps.
    %   - compute_erps must be called before compute_ga.
    %   - compute_ga must be called before most plots and contrasts.
    %
    % OUTPUTS AND SIDE EFFECTS
    %   - This class stores results in-memory in obj.Results.
    %   - It does not write files; caller is responsible for saving plots.
    %
    % SEE ALSO
    %   analysis.extract_epoch, analysis.Dataset

    properties
        Dataset     % An analysis.Dataset object containing the data and metadata.
        Selection   % A struct defining the analysis selections (groups, conditions, etc.).
        Results     % A struct to store all computed results (ERPs, GAs, contrasts, features).
    end

    methods
        function obj = ERPanalysis(dataset)
            if ~isa(dataset, 'analysis.Dataset')
                error('Input must be an analysis.Dataset object.');
            end
            obj.Dataset = dataset;
            obj.Selection.Groups = struct();
            obj.Selection.Conditions = {};
            obj.Selection.ROIs = struct();
            obj.Selection.TimeWindows = struct();
            obj.Results = struct();
            disp('ERPanalysis object created. Use define_group() and select_conditions() to set up your analysis.');
        end

        function obj = define_group(obj, group_name, subject_ids)
            arguments
                obj
                group_name char
                subject_ids cell
            end
            missing_subjects = setdiff(subject_ids, obj.Dataset.subjects);
            if ~isempty(missing_subjects)
                warning('The following subjects were not found in the Dataset and will be ignored: %s', strjoin(missing_subjects, ', '));
                subject_ids = intersect(subject_ids, obj.Dataset.subjects);
            end
            obj.Selection.Groups.(group_name) = subject_ids;
            fprintf('Group %s defined with %d subjects.\n', group_name, numel(subject_ids));
        end

        function obj = select_conditions(obj, condition_names)
             arguments
                obj
                condition_names cell
             end
             missing_conditions = setdiff(condition_names, obj.Dataset.conditions);
             if ~isempty(missing_conditions)
                warning('The following conditions were not found in the Dataset and will be ignored: %s', strjoin(missing_conditions, ', '));
                condition_names = intersect(condition_names, obj.Dataset.conditions);
             end
             obj.Selection.Conditions = condition_names;
             fprintf('Selected %d conditions for analysis.\n', numel(condition_names));
        end

        function obj = compute_erps(obj, varargin)
            p = inputParser;
            addParameter(p, 'averaging_method', 'mean', @(x) ismember(x, {'mean', 'median', 'trimmed'}));
            addParameter(p, 'trimmed_percent', 5, @isnumeric);
            parse(p, varargin{:});
            avg_method = p.Results.averaging_method;
            trimmed_percent = p.Results.trimmed_percent;
            fprintf('Computing subject-level ERPs using ''%s'' averaging...\n', avg_method);
            obj.Results.ERPs = struct();
            group_names = fieldnames(obj.Selection.Groups);
            if isempty(group_names), error('No groups defined. Use define_group() first.'); end
            if isempty(obj.Selection.Conditions), error('No conditions selected. Use select_conditions() first.'); end
            for g = 1:numel(group_names)
                group_name = group_names{g};
                subject_ids = obj.Selection.Groups.(group_name);
                for s = 1:numel(subject_ids)
                        subject_id = subject_ids{s};
                        for c = 1:numel(obj.Selection.Conditions)
                            condition_name = obj.Selection.Conditions{c};
                            trial_data = obj.Dataset.get_data(subject_id, condition_name);
                            if ~isempty(trial_data)
                                switch avg_method
                                    case 'mean', erp_data = mean(trial_data, 3);
                                    case 'median', erp_data = median(trial_data, 3);
                                    case 'trimmed', erp_data = trimmean(trial_data, trimmed_percent, 3);
                                end
                                sub_field = obj.subject_field(subject_id);
                                obj.Results.ERPs.(sub_field).(condition_name) = erp_data;
                            else
                                error('No data found for subject ''%s'', condition ''%s''. Cannot compute ERP.', subject_id, condition_name);
                            end
                        end
                end
            end
            fprintf('Done.\n');
        end

        function obj = compute_ga(obj)
            if ~isfield(obj.Results, 'ERPs') || isempty(fieldnames(obj.Results.ERPs))
                error('Subject-level ERPs not found. Please run compute_erps() first.');
            end
            fprintf('Computing Grand Average ERPs...\n');
            obj.Results.GA = struct();
            group_names = fieldnames(obj.Selection.Groups);
            for g = 1:numel(group_names)
                group_name = group_names{g};
                subject_ids = obj.Selection.Groups.(group_name);
                for c = 1:numel(obj.Selection.Conditions)
                    condition_name = obj.Selection.Conditions{c};
                    [erp_stack, ~] = obj.collect_subject_erps(subject_ids, condition_name);
                    if ~isempty(erp_stack)
                        ga_data = mean(erp_stack, 3);
                        obj.Results.GA.(group_name).(condition_name).erp = ga_data;
                        obj.Results.GA.(group_name).(condition_name).n = size(erp_stack, 3);
                    else
                        warning('No subject ERPs found for group ''%s'', condition ''%s''. Cannot compute GA.', group_name, condition_name);
                    end
                end
            end
            fprintf('Done.\n');
        end

        function plot_erp(obj, target_name, varargin)
            p = inputParser;
            addParameter(p, 'smoothing_factor', 1, @(x) isnumeric(x) && x >= 1);
            addParameter(p, 'show_error', 'se', @(x) ismember(x, {'se', 'std', 'none'}));
            addParameter(p, 'ErrorAlpha', 0.6, @isnumeric);
            addParameter(p, 'ErrorColor', [], @(x) isempty(x) || (isnumeric(x) && numel(x) == 3));
            parse(p, varargin{:});
            smoothing_factor = p.Results.smoothing_factor;
            show_error = p.Results.show_error;
            error_alpha = p.Results.ErrorAlpha;
            error_color = p.Results.ErrorColor;

            if ~isfield(obj.Results, 'GA') || isempty(fieldnames(obj.Results.GA))
                error('Grand Average results not found. Please run compute_ga() first.');
            end
            [chan_indices, plot_title_str] = obj.get_target_indices(target_name);
            times = obj.Dataset.times;
            group_names = fieldnames(obj.Results.GA);
            colors = get(groot,'defaultAxesColorOrder');
            for g = 1:numel(group_names)
                group_name = group_names{g};
                figure;
                hold on;
                condition_names = fieldnames(obj.Results.GA.(group_name));
                plot_handles = [];
                legend_labels = {};
                for c = 1:numel(condition_names)
                    condition_name = condition_names{c};
                    if isfield(obj.Results.GA.(group_name).(condition_name), 'erp')
                        ga_data = obj.Results.GA.(group_name).(condition_name).erp;
                        n = obj.Results.GA.(group_name).(condition_name).n;
                        waveform = mean(ga_data(chan_indices, :), 1);
                        if smoothing_factor > 1, waveform = smoothdata(waveform, 'movmean', smoothing_factor); end
                        
                        plot_color = colors(mod(c-1, size(colors,1))+1,:);
                        h = plot(times, waveform, 'LineWidth', 2, 'Color', plot_color, 'LineStyle', '-');
                        
                        if ~strcmp(show_error, 'none')
                            subject_ids = obj.Selection.Groups.(group_name);
                            [erp_stack, ~] = obj.collect_subject_erps(subject_ids, condition_name);
                            err_data = obj.calculate_error_band(show_error, erp_stack, chan_indices);
                            
                            final_error_color = error_color;
                            if isempty(final_error_color)
                                final_error_color = plot_color; 
                            end
                            
                            if ~isempty(err_data)
                                fill([times, fliplr(times)], [waveform-err_data, fliplr(waveform+err_data)], final_error_color, 'FaceAlpha', error_alpha, 'EdgeColor', 'none', 'HandleVisibility', 'off');
                            end
                        end
                        
                        plot_handles(end+1) = h;
                        legend_labels{end+1} = sprintf('%s (N=%d)', strrep(condition_name, '_', ' '), n);
                    end
                end
                hold off;
                set(gca, 'YDir', 'reverse');
                grid on; box on;
                xlabel('Time (ms)');
                ylabel('Amplitude (µV)');
                title(strrep(sprintf('ERP for %s (Group: %s)', plot_title_str, group_name), '_', ' '));
                legend(plot_handles, legend_labels, 'Location', 'best');
                ax = gca;
                hline = line(ax.XLim, [0 0], 'Color', 'k', 'LineStyle', '--');
                set(get(get(hline,'Annotation'),'LegendInformation'), 'IconDisplayStyle', 'off');
            end
        end

        function obj = define_roi(obj, roi_name, channel_labels)
            arguments
                obj
                roi_name char
                channel_labels cell
            end
            [valid_channels, missing_channels] = obj.validate_channels(channel_labels);
            if ~isempty(missing_channels)
                warning('For ROI ''%s'', the following channels were not found and will be ignored: %s', roi_name, strjoin(missing_channels, ', '));
            end
            if isempty(valid_channels)
                error('For ROI ''%s'', no valid channels were found. ROI not created.', roi_name);
            end
            obj.Selection.ROIs.(roi_name) = valid_channels;
            fprintf('ROI ''%s'' defined with %d channels.\n', roi_name, numel(valid_channels));
        end

        function obj = define_time_window(obj, window_name, time_range)
            arguments
                obj
                window_name char
                time_range (1,2) {mustBeNumeric, mustBeFinite}
            end
            if time_range(1) >= time_range(2), error('Time range must be [start, end] with start < end.'); end
            obj.Selection.TimeWindows.(window_name) = time_range;
            fprintf('Time window ''%s'' defined as [%d, %d] ms.\n', window_name, time_range(1), time_range(2));
        end

        function plot_topo(obj, varargin)
            p = inputParser;
            addRequired(p, 'obj');
            addParameter(p, 'time_window', '', @ischar);
            parse(p, obj, varargin{:});
            time_window_name = p.Results.time_window;
            if ~isfield(obj.Results, 'GA') || isempty(fieldnames(obj.Results.GA)), error('Grand Average results not found. Please run compute_ga() first.'); end
            if isempty(time_window_name) || ~isfield(obj.Selection.TimeWindows, time_window_name), error('A valid time window must be specified.'); end
            if ~exist('topoplot', 'file'), error('The EEGLAB function topoplot() is not in your MATLAB path.'); end
            time_range = obj.Selection.TimeWindows.(time_window_name);
            time_idx = obj.Dataset.times >= time_range(1) & obj.Dataset.times <= time_range(2);
            group_names = fieldnames(obj.Results.GA);
            num_groups = numel(group_names);
            condition_names = fieldnames(obj.Results.GA.(group_names{1}));
            num_conditions = numel(condition_names);
            figure('Position', [100, 100, 250 * num_conditions, 300 * num_groups]);
            plot_idx = 1;
            all_clim = [];
            for g = 1:num_groups
                group_name = group_names{g};
                condition_names = fieldnames(obj.Results.GA.(group_name));
                for c = 1:numel(condition_names)
                    condition_name = condition_names{c};
                    if isfield(obj.Results.GA.(group_name).(condition_name), 'erp')
                        ga_data = obj.Results.GA.(group_name).(condition_name).erp;
                        topo_data = mean(ga_data(:, time_idx), 2);
                        subplot(num_groups, num_conditions, plot_idx);
                        topoplot(double(topo_data), obj.Dataset.chanlocs, 'electrodes', 'on');
                        title_str = sprintf('%s: %s\n[%d-%d ms]', strrep(group_name, '_', ' '), strrep(condition_name, '_', ' '), time_range(1), time_range(2));
                        title(title_str);
                        ax = gca;
                        all_clim = [all_clim; ax.CLim];
                    end
                    plot_idx = plot_idx + 1;
                end
            end
            max_abs_lim = max(abs(all_clim(:)));
            if isempty(max_abs_lim) || max_abs_lim == 0, max_abs_lim = 1; end
            synchronized_clim = [-max_abs_lim, max_abs_lim];
            for i = 1:(plot_idx-1)
                h_subplot = subplot(num_groups, num_conditions, i);
                caxis(h_subplot, synchronized_clim);
                colorbar;
            end
        end

        function show_channels(obj, varargin)
            if isprop(obj,'Dataset') && ~isempty(obj.Dataset) && isprop(obj.Dataset,'chanlocs') && numel(obj.Dataset.chanlocs) > 0
                chanlocs = obj.Dataset.chanlocs;
            else
                error('chanlocs missing/empty');
            end
            ROI_selector(chanlocs, varargin{:});
        end


        function obj = compute_contrast(obj, contrast_name, positive_term, negative_term)
            arguments
                obj
                contrast_name char
                positive_term cell
                negative_term cell
            end
            if ~isfield(obj.Results, 'GA'), error('Grand Average results not found. Please run compute_ga() first.'); end
            [pos_erp, pos_n] = obj.get_ga_term(positive_term);
            [neg_erp, neg_n] = obj.get_ga_term(negative_term);
            diff_wave = pos_erp - neg_erp;
            obj.Results.Contrasts.(contrast_name).erp = diff_wave;
            obj.Results.Contrasts.(contrast_name).positive_term = positive_term;
            obj.Results.Contrasts.(contrast_name).negative_term = negative_term;
            obj.Results.Contrasts.(contrast_name).n_positive = pos_n;
            obj.Results.Contrasts.(contrast_name).n_negative = neg_n;
            fprintf('Contrast ''%s'' computed.\n', contrast_name);
        end

        function plot_contrast_erp(obj, contrast_name, varargin)
            p = inputParser;
            addRequired(p, 'obj');
            addRequired(p, 'contrast_name', @ischar);
            addParameter(p, 'target_name', '', @ischar);
            addParameter(p, 'show_sig', true, @islogical);
            addParameter(p, 'sig_alpha', 0.6, @isnumeric);
            addParameter(p, 'sig_color', [0.8 0.8 0.8], @isnumeric);
            addParameter(p, 'time_window', [], @(x) isempty(x) || (isnumeric(x) && numel(x) == 2));
            addParameter(p, 'smoothing_factor', 1, @(x) isnumeric(x) && x >= 1);
            addParameter(p, 'show_error', 'se', @(x) ismember(x, {'se', 'std', 'none'}));
            addParameter(p, 'ErrorAlpha', 0.6, @isnumeric);
            addParameter(p, 'ErrorColor', [], @(x) isempty(x) || (isnumeric(x) && numel(x) == 3));
            addParameter(p, 'highlight_time_windows', [], @(x) isempty(x) || (isnumeric(x) && size(x,2) == 2));
            addParameter(p, 'show_diff', false, @islogical);
            addParameter(p, 'show_topo', true, @islogical);

            parse(p, obj, contrast_name, varargin{:});
            
            if ~isfield(obj.Results.Contrasts, contrast_name)
                error('Contrast ''%s'' not found. Please run compute_contrast() first.', contrast_name);
            end
            
            if isempty(p.Results.target_name)
                contrast_def = obj.Results.Contrasts.(contrast_name);
                stats_exist = isfield(contrast_def, 'Stats') && isfield(contrast_def.Stats, 'h');
                if ~stats_exist, error('A target_name must be provided, or stats computed.'); end
                if ~isempty(contrast_def.Stats.roi), error('Stats were computed on an ROI. Specify that ROI as target_name.'); end
                
                sig_ch_idx = find(any(contrast_def.Stats.h, 2));
                if isempty(sig_ch_idx), fprintf('No significant channels found.\n'); return; end
                
                sig_ch_labels = {obj.Dataset.chanlocs(sig_ch_idx).labels};
                num_sig_chans = numel(sig_ch_labels);
                fprintf('Plotting %d significant channels.\n', num_sig_chans);
                
                figure('Position', [100, 100, 400 * min(num_sig_chans, 4), 300 * ceil(num_sig_chans / 4)]);
                n_cols = ceil(sqrt(num_sig_chans));
                n_rows = ceil(num_sig_chans / n_cols);

                for i = 1:num_sig_chans
                    ax = subplot(n_rows, n_cols, i);
                    plot_options = p.Results;
                    plot_options.target_name = sig_ch_labels{i};
                    obj.plot_single_contrast_on_ax(ax, contrast_name, plot_options);
                end
                sgtitle(sprintf('Significant Channels for Contrast: %s', strrep(contrast_name, '_', ' ')));

            else
                figure;
                ax = gca;
                obj.plot_single_contrast_on_ax(ax, contrast_name, p.Results);
            end
        end

        function features_table = extract_feature(obj, varargin)
            p = inputParser;
            addParameter(p, 'roi', '', @ischar);
            addParameter(p, 'time_window', '', @ischar);
            addParameter(p, 'feature_func', 'mean', @(x) ischar(x) || isa(x, 'function_handle'));
            addParameter(p, 'peak_polarity', 'max', @(x) ismember(x, {'max', 'min'}));
            parse(p, varargin{:});
            roi_name = p.Results.roi;
            time_window_name = p.Results.time_window;
            feature_func = p.Results.feature_func;
            peak_polarity = p.Results.peak_polarity;

            if ~isfield(obj.Results, 'ERPs'), error('Run compute_erps() first.'); end
            if isempty(roi_name) || ~isfield(obj.Selection.ROIs, roi_name), error('Specify a valid ROI.'); end
            if isempty(time_window_name) || ~isfield(obj.Selection.TimeWindows, time_window_name), error('Specify a valid time window.'); end

            fprintf('Extracting features for ROI ''%s'' in window ''%s''...\n', roi_name, time_window_name);
            [chan_indices, ~] = obj.get_target_indices(roi_name);
            time_range = obj.Selection.TimeWindows.(time_window_name);
            time_indices = obj.Dataset.times >= time_range(1) & obj.Dataset.times <= time_range(2);
            times_in_window = obj.Dataset.times(time_indices);

            results_list = {};
            group_names = fieldnames(obj.Selection.Groups);
            for g = 1:numel(group_names)
                group_name = group_names{g};
                subject_ids = obj.Selection.Groups.(group_name);
                for s = 1:numel(subject_ids)
                    subject_id = subject_ids{s};
                    sub_field = obj.subject_field(subject_id);
                    for c = 1:numel(obj.Selection.Conditions)
                        condition_name = obj.Selection.Conditions{c};
                        if isfield(obj.Results.ERPs, sub_field) && isfield(obj.Results.ERPs.(sub_field), condition_name)
                            subject_erp = obj.Results.ERPs.(sub_field).(condition_name);
                            roi_erp = mean(subject_erp(chan_indices, time_indices), 1);
                            if isa(feature_func, 'function_handle')
                                feature_values = feature_func(roi_erp, times_in_window);
                            else
                                switch lower(feature_func)
                                    case 'mean', feature_values = mean(roi_erp);
                                    case 'median', feature_values = median(roi_erp);
                                    case 'peak'
                                        if strcmp(peak_polarity, 'max'), [val, idx] = max(roi_erp); else, [val, idx] = min(roi_erp); end
                                        feature_values = [val, times_in_window(idx)];
                                    case 'latency'
                                        if strcmp(peak_polarity, 'max'), [~, idx] = max(roi_erp); else, [~, idx] = min(roi_erp); end
                                        feature_values = times_in_window(idx);
                                    otherwise, error('Unknown feature: %s', feature_func);
                                end
                            end
                            results_list(end+1, :) = {subject_id, group_name, condition_name, feature_values};
                        end
                    end
                end
            end

            if isempty(results_list), warning('No data found to extract features.'); features_table = table(); return; end
            base_vars = {'SubjectID', 'Group', 'Condition'};
            if isa(feature_func, 'char') && strcmp(feature_func, 'peak')
                feature_names = {[roi_name '_' time_window_name '_' feature_func '_amp'], [roi_name '_' time_window_name '_' feature_func '_' 'lat']};
                temp_results = [results_list{:,4}];
                flat_results = [results_list(:,1:3), num2cell(reshape(temp_results, [], 2))];
            else
                if isa(feature_func,'char')
                    feature_name_str = feature_func;
                else
                    feature_name_str = func2str(feature_func);
                end
                feature_names = {[roi_name '_' time_window_name '_' feature_name_str]};
                flat_results = [results_list(:,1:3), num2cell([results_list{:,4}]')];
            end
            features_table = cell2table(flat_results, 'VariableNames', [base_vars, feature_names]);
            if isa(feature_func,'char')
                feature_field_name = [roi_name '_' time_window_name '_' feature_func];
            else
                feature_field_name = [roi_name '_' time_window_name '_' func2str(feature_func)];
            end
            obj.Results.Features.(feature_field_name) = features_table;
            fprintf('Done. Feature table created with %d rows.\n', height(features_table));
        end

        function obj = compute_stats(obj, varargin)
            if ~exist('ttest', 'file'), error('This method requires the Statistics and Machine Learning Toolbox.'); end
            p = inputParser;
            addParameter(p, 'contrast', '', @ischar);
            addParameter(p, 'roi', '', @ischar); % New parameter
            addParameter(p, 'alpha', 0.05, @isnumeric);
            addParameter(p, 'mcc', 'none', @(x) ismember(x, {'fdr', 'none'}));
            addParameter(p, 'time_window', [], @(x) isempty(x) || (isnumeric(x) && numel(x) == 2));
            parse(p, varargin{:});
            contrast_name = p.Results.contrast;
            roi_name = p.Results.roi;
            alpha = p.Results.alpha;
            mcc = p.Results.mcc;
            time_window = p.Results.time_window;

            if isempty(contrast_name) || ~isfield(obj.Results.Contrasts, contrast_name), error('Specify a valid contrast name.'); end
            fprintf('Computing stats for contrast ''%s''...\n', strrep(contrast_name, '_', ' '));
            contrast_def = obj.Results.Contrasts.(contrast_name);
            pos_group = contrast_def.positive_term{1}; pos_cond = contrast_def.positive_term{2};
            neg_group = contrast_def.negative_term{1}; neg_cond = contrast_def.negative_term{2};
            pos_subjects = obj.Selection.Groups.(pos_group);
            neg_subjects = obj.Selection.Groups.(neg_group);

            [pos_data, pos_subs_found] = obj.collect_subject_erps(pos_subjects, pos_cond);
            [neg_data, neg_subs_found] = obj.collect_subject_erps(neg_subjects, neg_cond);

            data_dim = 3;
            if ~isempty(roi_name)
                if ~isfield(obj.Selection.ROIs, roi_name), error('ROI ''%s'' not found. Define it first with define_roi().', roi_name);end
                [chan_indices, ~] = obj.get_target_indices(roi_name);
                fprintf('Computing stats on average of ROI ''%s'' (%d channels).\n', roi_name, numel(chan_indices));
                pos_data = squeeze(mean(pos_data(chan_indices, :, :), 1));
                neg_data = squeeze(mean(neg_data(chan_indices, :, :), 1));
                data_dim = 2;
            end

            is_paired = isequal(pos_subjects, neg_subjects) && strcmp(pos_group, neg_group);

            if is_paired
                [common_subs, ia, ib] = intersect(pos_subs_found, neg_subs_found, 'stable');
                if numel(common_subs) < numel(pos_subs_found) || numel(common_subs) < numel(neg_subs_found)
                    warning('Unequal subjects for paired test. Using %d common subjects.', numel(common_subs));
                end
                if data_dim == 3
                    pos_data_paired = pos_data(:,:,ia);
                    neg_data_paired = neg_data(:,:,ib);
                else
                    pos_data_paired = pos_data(:,ia);
                    neg_data_paired = neg_data(:,ib);
                end
                diff_data = pos_data_paired - neg_data_paired;
                [~, p, ~, stats] = ttest(diff_data, 0, 'dim', data_dim);
                t = stats.tstat;
            else
                [~, p, ~, stats] = ttest2(pos_data, neg_data, 'dim', data_dim);
                t = stats.tstat;
            end

            time_indices = 1:size(obj.Dataset.times, 2);
            if ~isempty(time_window)
                time_indices = obj.Dataset.times >= time_window(1) & obj.Dataset.times <= time_window(2);
                if data_dim == 3
                    p = p(:, time_indices);
                    t = t(:, time_indices);
                else
                    p = p(time_indices);
                    t = t(time_indices);
                end
            end

            p_corrected = nan(size(p));
            if strcmp(mcc, 'fdr')
                p_vector = p(:);
                nan_mask = isnan(p_vector);
                p_vector_nonan = p_vector(~nan_mask);
                if ~isempty(p_vector_nonan)
                    p_corrected_vector = mafdr(p_vector_nonan, 'BHFDR', true);
                    p_corrected_nonan = nan(size(p_vector));
                    p_corrected_nonan(~nan_mask) = p_corrected_vector;
                    p_corrected = reshape(p_corrected_nonan, size(p));
                else, warning('All p-values were NaN; FDR correction not applied.');
                end
            else, p_corrected = p;
            end
            h = p_corrected < alpha;

            tvec = obj.Dataset.times(time_indices);
            sig_clusters = cell(size(h,1), 1);
            any_found = false;
            for ch = 1:size(h,1) 
                edges = diff([0 h(ch,:) 0]);
                starts = find(edges == 1);
                ends = find(edges == -1);
                if ~isempty(starts)
                    any_found = true;
                    clusters = [tvec(starts)', tvec(ends-1)'];
                    sig_clusters{ch} = clusters;
                    if isempty(roi_name)
                        fprintf('Ch %s: %d significant cluster(s):\n', obj.Dataset.chanlocs(ch).labels, numel(starts));
                    else
                        fprintf('ROI %s: %d significant cluster(s):\n', roi_name, numel(starts));
                    end
                    for k = 1:numel(starts)
                        fprintf('  %d–%d ms\n', round(clusters(k,1)), round(clusters(k,2)));
                    end
                end
            end
            if ~any_found
                fprintf('No significant clusters found.\n');
            end

            if ~isempty(roi_name)
                num_chans = 1;
            else
                num_chans = numel(obj.Dataset.chanlocs);
            end
            full_p = nan(num_chans, numel(obj.Dataset.times));
            full_t = nan(num_chans, numel(obj.Dataset.times));
            full_h = false(num_chans, numel(obj.Dataset.times));
            full_p_corrected = nan(num_chans, numel(obj.Dataset.times));
            full_p(:, time_indices) = p;
            full_t(:, time_indices) = t;
            full_h(:, time_indices) = h;
            full_p_corrected(:, time_indices) = p_corrected;

            obj.Results.Contrasts.(contrast_name).Stats.p = full_p;
            obj.Results.Contrasts.(contrast_name).Stats.p_corrected = full_p_corrected;
            obj.Results.Contrasts.(contrast_name).Stats.t = full_t;
            obj.Results.Contrasts.(contrast_name).Stats.h = full_h;
            obj.Results.Contrasts.(contrast_name).Stats.sig_clusters = sig_clusters; 
            obj.Results.Contrasts.(contrast_name).Stats.alpha = alpha;
            obj.Results.Contrasts.(contrast_name).Stats.mcc = mcc;
            obj.Results.Contrasts.(contrast_name).Stats.is_paired = is_paired;
            obj.Results.Contrasts.(contrast_name).Stats.time_window = time_window;
            obj.Results.Contrasts.(contrast_name).Stats.roi = roi_name;
            fprintf('Done. Found %d significant channel-time points.\n', sum(h(:)));
        end
    end

    methods (Access = private)
        function plot_single_contrast_on_ax(obj, ax, contrast_name, plot_options)
            target_name = plot_options.target_name;
            show_sig = plot_options.show_sig;
            sig_alpha = plot_options.sig_alpha;
            sig_color = plot_options.sig_color;
            time_window = plot_options.time_window;
            smoothing_factor = plot_options.smoothing_factor;
            show_error = plot_options.show_error;
            error_alpha = plot_options.ErrorAlpha;
            error_color = plot_options.ErrorColor;
            highlight_time_windows = plot_options.highlight_time_windows;
            show_diff = plot_options.show_diff;
            show_topo = plot_options.show_topo;

            contrast_def = obj.Results.Contrasts.(contrast_name);
            stats_exist = isfield(contrast_def, 'Stats') && isfield(contrast_def.Stats, 'h');
            
            if show_sig && ~stats_exist
                warning('Significance data not found. Significance will not be shown.');
                show_sig = false;
            end

            [chan_indices, plot_title_str] = obj.get_target_indices(target_name);
            times = obj.Dataset.times;
            
            pos_term = contrast_def.positive_term;
            neg_term = contrast_def.negative_term;
            [pos_erp, ~] = obj.get_ga_term(pos_term);
            [neg_erp, ~] = obj.get_ga_term(neg_term);
            pos_waveform = mean(pos_erp(chan_indices, :), 1);
            neg_waveform = mean(neg_erp(chan_indices, :), 1);
            diff_waveform = mean(contrast_def.erp(chan_indices, :), 1);

            if smoothing_factor > 1
                pos_waveform = smoothdata(pos_waveform, 'movmean', smoothing_factor);
                neg_waveform = smoothdata(neg_waveform, 'movmean', smoothing_factor);
                diff_waveform = smoothdata(diff_waveform, 'movmean', smoothing_factor);
            end
            
            hold(ax, 'on');
            
            colors = get(groot,'defaultAxesColorOrder');
            h_pos = plot(ax, times, pos_waveform, 'LineWidth', 2, 'Color', colors(1,:));
            h_neg = plot(ax, times, neg_waveform, 'LineWidth', 2, 'Color', colors(2,:));
            if show_diff
                h_diff = plot(ax, times, diff_waveform, 'LineWidth', 2, 'Color', 'k', 'LineStyle', '-');
            else
                h_diff = [];
            end

            if ~strcmp(show_error, 'none')
                pos_subject_ids = obj.Selection.Groups.(pos_term{1});
                [pos_erp_stack, ~] = obj.collect_subject_erps(pos_subject_ids, pos_term{2});
                pos_err = obj.calculate_error_band(show_error, pos_erp_stack, chan_indices);
                
                final_pos_error_color = error_color;
                if isempty(final_pos_error_color), final_pos_error_color = h_pos.Color; end
                if ~isempty(pos_err)
                    fill(ax, [times, fliplr(times)], [pos_waveform - pos_err, fliplr(pos_waveform + pos_err)], final_pos_error_color, 'FaceAlpha', error_alpha, 'EdgeColor', 'none', 'HandleVisibility', 'off');
                end
                
                neg_subject_ids = obj.Selection.Groups.(neg_term{1});
                [neg_erp_stack, ~] = obj.collect_subject_erps(neg_subject_ids, neg_term{2});
                neg_err = obj.calculate_error_band(show_error, neg_erp_stack, chan_indices);

                final_neg_error_color = error_color;
                if isempty(final_neg_error_color), final_neg_error_color = h_neg.Color; end
                if ~isempty(neg_err)
                    fill(ax, [times, fliplr(times)], [neg_waveform - neg_err, fliplr(neg_waveform + neg_err)], final_neg_error_color, 'FaceAlpha', error_alpha, 'EdgeColor', 'none', 'HandleVisibility', 'off');
                end
            end

            if ~strcmp(show_error, 'none') && stats_exist && show_diff
                is_paired = contrast_def.Stats.is_paired;
                if is_paired
                    [pos_erp_stack, ~] = obj.collect_subject_erps(obj.Selection.Groups.(pos_term{1}), pos_term{2});
                    [neg_erp_stack, ~] = obj.collect_subject_erps(obj.Selection.Groups.(neg_term{1}), neg_term{2});
                    diff_stack = pos_erp_stack - neg_erp_stack;
                    diff_err = obj.calculate_error_band(show_error, diff_stack, chan_indices);
                    
                    final_diff_error_color = error_color;
                    if isempty(final_diff_error_color), final_diff_error_color = [0.5 0.5 0.5]; end
                    if ~isempty(diff_err)
                        fill(ax, [times, fliplr(times)], [diff_waveform - diff_err, fliplr(diff_waveform + diff_err)], final_diff_error_color, 'FaceAlpha', error_alpha, 'EdgeColor', 'none', 'HandleVisibility', 'off');
                    end
                else
                    if strcmp(show_error, 'se')
                        diff_err = sqrt(pos_err.^2 + neg_err.^2);
                        final_diff_error_color = error_color;
                        if isempty(final_diff_error_color), final_diff_error_color = [0.5 0.5 0.5]; end
                        if ~isempty(diff_err)
                            fill(ax, [times, fliplr(times)], [diff_waveform - diff_err, fliplr(diff_waveform + diff_err)], final_diff_error_color, 'FaceAlpha', error_alpha, 'EdgeColor', 'none', 'HandleVisibility', 'off');
                        end
                    else
                        warning('Cannot show STD of difference for an unpaired contrast. Error band for difference wave omitted.');
                    end
                end
            end
            
            if ~isempty(time_window), xlim(ax, time_window); end
            set(ax, 'YDir', 'reverse');
            
            windows_to_highlight = [];
            if ~isempty(highlight_time_windows)
                windows_to_highlight = highlight_time_windows;
            elseif show_sig
                stats = contrast_def.Stats;
                if ~isempty(stats.roi) && ~strcmp(stats.roi, target_name)
                     warning('Stats were computed on ROI ''%s'', but plotting target is ''%s''. Significance shading may not be appropriate.', stats.roi, target_name);
                end

                if ~isempty(stats.roi)
                    sig_mask = stats.h(1, :);
                else
                    sig_mask = any(stats.h(chan_indices, :), 1);
                end
                windows_to_highlight = obj.get_sig_windows(sig_mask, times);
            end

            if ~isempty(windows_to_highlight)
                yl = ylim(ax);
                for i = 1:size(windows_to_highlight, 1)
                    win = windows_to_highlight(i,:);
                    x_area = [win(1), win(2)];
                    area(ax, x_area, [yl(2) yl(2)] , 'FaceColor', sig_color, 'FaceAlpha', sig_alpha,  'HandleVisibility', 'off');
                    area(ax, x_area, [yl(1) yl(1)] , 'FaceColor', sig_color, 'FaceAlpha', sig_alpha,  'HandleVisibility', 'off');
    
                end
                if show_topo
                    obj.plot_contrast_topos_for_windows(contrast_name, windows_to_highlight);
                end
            end

            hold(ax, 'off');
            
            grid(ax, 'on'); box(ax, 'on');
            xlabel(ax, 'Time (ms)');
            ylabel(ax, 'Amplitude (µV)');
            title(ax, strrep(sprintf('%s (%s)', contrast_name, plot_title_str), '_', ' '));
            legend_handles = [h_pos, h_neg];
            legend_labels = {strrep(pos_term{2}, '_', ' '), strrep(neg_term{2}, '_', ' ')};
            if show_diff
                legend_handles(end+1) = h_diff;
                legend_labels{end+1} = strrep(contrast_name, '_', ' ');
            end
            legend(ax, legend_handles, legend_labels, 'Location', 'best');
            hline = line(ax, ax.XLim, [0 0], 'Color', 'k', 'LineStyle', '--');
            set(get(get(hline,'Annotation'),'LegendInformation'), 'IconDisplayStyle', 'off');
        end

        function plot_contrast_topos_for_windows(obj, contrast_name, time_windows)
            if ~exist('topoplot', 'file'), error('The EEGLAB function topoplot() is not in your MATLAB path.'); end

            contrast_def = obj.Results.Contrasts.(contrast_name);
            pos_term = contrast_def.positive_term;
            neg_term = contrast_def.negative_term;
            [pos_erp, ~] = obj.get_ga_term(pos_term);
            [neg_erp, ~] = obj.get_ga_term(neg_term);
            diff_erp = contrast_def.erp;

            times = obj.Dataset.times;
            num_windows = size(time_windows, 1);

            if num_windows == 0, return; end

            figure('Name', sprintf('Topographies for %s', contrast_name));
            
            all_axes = [];
            all_clim = [];

            for i = 1:num_windows
                time_range = time_windows(i, :);
                time_idx = times >= time_range(1) & times <= time_range(2);

                % Positive condition
                ax1 = subplot(num_windows, 3, (i-1)*3 + 1);
                topo_data_pos = mean(pos_erp(:, time_idx), 2);
                topoplot(double(topo_data_pos), obj.Dataset.chanlocs, 'electrodes', 'on');
                title(sprintf('%s\n%d-%d ms', strrep(pos_term{2}, '_', ' '), round(time_range(1)), round(time_range(2))));
                all_axes = [all_axes, ax1];
                all_clim = [all_clim; caxis];

                % Negative condition
                ax2 = subplot(num_windows, 3, (i-1)*3 + 2);
                topo_data_neg = mean(neg_erp(:, time_idx), 2);
                topoplot(double(topo_data_neg), obj.Dataset.chanlocs, 'electrodes', 'on');
                title(sprintf('%s\n%d-%d ms', strrep(neg_term{2}, '_', ' '), round(time_range(1)), round(time_range(2))));
                all_axes = [all_axes, ax2];
                all_clim = [all_clim; caxis];

                % Difference
                ax3 = subplot(num_windows, 3, (i-1)*3 + 3);
                topo_data_diff = mean(diff_erp(:, time_idx), 2);
                topoplot(double(topo_data_diff), obj.Dataset.chanlocs, 'electrodes', 'on');
                title(sprintf('Difference\n%d-%d ms', round(time_range(1)), round(time_range(2))));
                all_axes = [all_axes, ax3];
                all_clim = [all_clim; caxis];
            end

            max_abs_lim = max(abs(all_clim(:)));
            if isempty(max_abs_lim) || max_abs_lim == 0, max_abs_lim = 1; end
            synchronized_clim = [-max_abs_lim, max_abs_lim];

            for i = 1:length(all_axes)
                caxis(all_axes(i), synchronized_clim);
                colorbar('peer', all_axes(i));
            end
        end

        function [valid_channels, missing_channels] = validate_channels(obj, channel_labels)
            dataset_channels = {obj.Dataset.chanlocs.labels};
            is_member = ismember(channel_labels, dataset_channels);
            valid_channels = channel_labels(is_member);
            missing_channels = channel_labels(~is_member);
        end

        function [erp_data, n] = get_ga_term(obj, term)
            if numel(term) ~= 2 || ~ischar(term{1}) || ~ischar(term{2})
                error('A contrast term must be a cell array like {''GroupName'', ''ConditionName''}.');
            end
            group_name = term{1}; condition_name = term{2};
            if ~isfield(obj.Results.GA, group_name) || ~isfield(obj.Results.GA.(group_name), condition_name)
                error('The term %s:%s was not found in the computed Grand Averages.', group_name, condition_name);
            end
            erp_data = obj.Results.GA.(group_name).(condition_name).erp;
            n = obj.Results.GA.(group_name).(condition_name).n;
        end

        function [erp_stack, subjects_found] = collect_subject_erps(obj, subject_ids, condition_name)
            erp_cell = {};
            subjects_found = {};
            for i = 1:numel(subject_ids)
                sub_id = subject_ids{i};
                sub_field = obj.subject_field(sub_id);
                if isfield(obj.Results.ERPs, sub_field) && isfield(obj.Results.ERPs.(sub_field), condition_name)
                    erp_cell{end+1} = obj.Results.ERPs.(sub_field).(condition_name);
                    subjects_found{end+1} = sub_id;
                else
                    warning('ERP data for subject %s, condition %s not found. Skipping.', sub_id, condition_name);
                end
            end
            if ~isempty(erp_cell)
                erp_stack = cat(3, erp_cell{:});
            else
                erp_stack = [];
            end
        end

        function sub_field = subject_field(obj, subject_id)
            sub_field = subject_id;
            if isfield(obj.Dataset.data, sub_field)
                return;
            end
            if startsWith(subject_id, 'sub_')
                stripped = subject_id(5:end);
                if isfield(obj.Dataset.data, stripped)
                    sub_field = stripped;
                end
                return;
            end
            prefixed = ['sub_' subject_id];
            if isfield(obj.Dataset.data, prefixed)
                sub_field = prefixed;
            end
        end

        function [chan_indices, title_str] = get_target_indices(obj, target_name)
            is_roi = isfield(obj.Selection.ROIs, target_name);
            if is_roi
                channel_labels = obj.Selection.ROIs.(target_name);
                [valid_channels, ~] = obj.validate_channels(channel_labels);
                chan_indices = find(ismember({obj.Dataset.chanlocs.labels}, valid_channels));
                title_str = sprintf('ROI: %s', target_name);
            else
                [valid_channels, ~] = obj.validate_channels({target_name});
                if isempty(valid_channels), error('Channel ''%s'' not found.', target_name); end
                chan_indices = find(strcmp({obj.Dataset.chanlocs.labels}, valid_channels{1}));
                title_str = sprintf('Channel: %s', target_name);
            end
            if isempty(chan_indices), error('No valid channels found for ''%s''.', target_name); end
        end

        function err_band = calculate_error_band(obj, error_type, erp_stack, chan_indices)
            if isempty(erp_stack)
                err_band = [];
                return;
            end
            n = size(erp_stack, 3);
            roi_data = squeeze(mean(erp_stack(chan_indices,:,:), 1));
            
            if strcmp(error_type, 'se')
                err_band = std(roi_data, 0, 2)' / sqrt(n);
            else % 'std'
                err_band = std(roi_data, 0, 2)';
            end
        end

        function windows = get_sig_windows(obj, sig_mask, times)
            sig_mask = logical(sig_mask(:)');
            sig_starts = find(diff([0 sig_mask 0])==1);
            sig_ends   = find(diff([0 sig_mask 0])==-1);
            windows = [];
            for i = 1:numel(sig_starts)
                t_start = times(sig_starts(i));
                t_end = times(sig_ends(i)-1);
                windows = [windows; t_start, t_end];
            end
        end
    end
end
