classdef TFanalysis
    % TFANALYSIS — Time-Frequency (T-F) analysis helper for Out_tfd datasets (cftt)
    %
    % Works with analysis.run_tfr() outputs:
    %   .sub_<ID>.<cond>.power           [chan x f x t]
    %   .sub_<ID>.<cond>.itc             [chan x f x t]
    %   .sub_<ID>.<cond>.power_trials    [chan x f x t x trials]  (optional)
    %   .sub_<ID>.<cond>.phase           [chan x f x t x trials]  (optional)
    %   .sub_<ID>.<cond>.tf_complex      [chan x f x t x trials]  (optional)
    %   .meta.freqs (Hz), .meta.times (ms), .meta.axis='cftt'
    %
    % Key additions:
    %   - Selection API (groups/conds/ROIs/time windows/freq bands)
    %   - Visualization: TFR, contrast TFR, band-timecourse (mean ± CI), topomap
    %   - Features: band/time ROI means, peaks, AUC → table
    %   - Stats: ROI×band t-tests (paired/unpaired) with FDR, TFCE hook
    %
    % Example:
    %   ds_tfd = analysis.Dataset(Out_tfd);                % wrap TFR output
    %   tf = TFanalysis(ds_tfd) ...
    %        .define_group('All', ds_tfd.get_subjects()) ...
    %        .select_conditions({'loss_cue','win_cue'}) ...
    %        .define_roi('Midline', {'Fz','FCz','Cz'}) ...
    %        .define_freq_band('Alpha',[8 12]) ...
    %        .define_time_window('Early',[200 600]);
    %
    %   % Grand-average TFR over ROI
    %   tf = tf.compute_ga_tfd();
    %   tf.plot_tfr('Midline','group','All','condition','loss_cue',...
    %               'freq_range',[2 30],'x_range',[-500 1500]);
    %
    %   % Band-timecourse with CI (ROI Alpha)
    %   tf.plot_band_timecourse('Midline','Alpha','loss_cue','All',...
    %                           'x_range',[-500 1500],'ci','sem');
    %
    %   % Topomap of Alpha 300–600 ms
    %   tf.plot_topomap_band('Alpha',[300 600],'loss_cue','All');
    %
    %   % Define contrast and run ROI×band stats (FDR)
    %   tf = tf.define_contrast('LossMinusWin', {'All','loss_cue'}, {'All','win_cue'});
    %   tf = tf.compute_band_stats('LossMinusWin','Midline','Alpha','paired',true,'alpha',0.05);
    %   tf.plot_contrast_tfr('LossMinusWin','Midline','freq_range',[4 30]);
    %
    %   % Extract features to table
    %   T = tf.extract_features('roi','Midline','band','Alpha','window','Early',...
    %                           'metrics',{'mean','peak','auc'});
    %

    properties
        Dataset     % analysis.Dataset wrapping Out_tfd
        Selection   % struct of groups/conds/ROIs/time windows/freq bands
        Results     % struct for computed GA, contrasts, stats, features
    end

    methods
        function obj = TFanalysis(dataset)
            if ~isa(dataset, 'analysis.Dataset')
                error('Input must be an analysis.Dataset (wrapping Out_tfd).');
            end
            if ~isfield(dataset.data, 'meta') || ~isfield(dataset.data.meta, 'freqs') || ~isfield(dataset.data.meta, 'times')
                error('Dataset.meta must contain freqs (Hz) and times (ms).');
            end
            obj.Dataset = dataset;

            obj.Selection = struct();
            obj.Selection.Groups      = struct(); % name -> cellstr subject IDs
            obj.Selection.Conditions  = {};
            obj.Selection.ROIs        = struct(); % name -> cellstr of labels
            obj.Selection.TimeWindows = struct(); % name -> [t1 t2] ms
            obj.Selection.FreqBands   = struct(); % name -> [f1 f2] Hz

            obj.Results = struct();
            disp('TFanalysis (cftt) initialized.');
        end

        % ---------------- Selection API ----------------
        function obj = define_group(obj, group_name, subject_ids)
            arguments, obj, group_name char, subject_ids cell, end
            [valid, missing] = obj.validate_subjects(subject_ids);
            if ~isempty(missing)
                warning('define_group: missing subjects ignored: %s', strjoin(missing, ', '));
            end
            obj.Selection.Groups.(group_name) = valid;
            fprintf('Group "%s": %d subjects.\n', group_name, numel(valid));
        end

        function obj = select_conditions(obj, condition_names)
            arguments, obj, condition_names cell, end
            [valid, missing] = obj.validate_conditions(condition_names);
            if ~isempty(missing)
                warning('select_conditions: missing conditions ignored: %s', strjoin(missing, ', '));
            end
            obj.Selection.Conditions = valid;
            fprintf('Selected %d conditions.\n', numel(valid));
        end

        function obj = define_roi(obj, roi_name, channel_labels)
            arguments, obj, roi_name char, channel_labels cell, end
            [valid, missing] = obj.validate_channels(channel_labels);
            if ~isempty(missing)
                warning('ROI "%s": missing channels ignored: %s', roi_name, strjoin(missing, ', '));
            end
            if isempty(valid), error('ROI "%s" has no valid channels.', roi_name); end
            obj.Selection.ROIs.(roi_name) = valid;
            fprintf('ROI "%s": %d channels.\n', roi_name, numel(valid));
        end

        function obj = define_time_window(obj, window_name, time_range)
            arguments, obj, window_name char, time_range (1,2) {mustBeNumeric,mustBeFinite}, end
            if time_range(1) >= time_range(2), error('Time window must be [start<end].'); end
            obj.Selection.TimeWindows.(window_name) = time_range;
            fprintf('Time window "%s": [%g %g] ms.\n', window_name, time_range(1), time_range(2));
        end

        function obj = define_freq_band(obj, band_name, freq_range)
            arguments, obj, band_name char, freq_range (1,2) {mustBeNumeric,mustBeFinite}, end
            if freq_range(1) >= freq_range(2), error('Freq band must be [low<high].'); end
            obj.Selection.FreqBands.(band_name) = freq_range;
            fprintf('Band "%s": [%.2f %.2f] Hz.\n', band_name, freq_range(1), freq_range(2));
        end

        % ---------------- GA computation ----------------
        function obj = compute_ga_tfd(obj, varargin)
            % COMPUTE_GA_TFD  Grand-average [chan x f x t], stored in Results.GA_TFD
            % Options:
            %   'metric'   'power'|'itc'|'evoked_power'|'induced_power' (default 'power')
            p = inputParser;
            addParameter(p, 'metric', 'power', @(s)ischar(s));
            parse(p, varargin{:});
            metric = p.Results.metric;

            if isempty(fieldnames(obj.Selection.Groups)), error('No groups defined.'); end
            if isempty(obj.Selection.Conditions), error('No conditions selected.'); end

            freqs = obj.Dataset.data.meta.freqs;
            times = obj.Dataset.data.meta.times;

            obj.Results.GA_TFD = struct();
            gnames = fieldnames(obj.Selection.Groups);
            for g = 1:numel(gnames)
                G = gnames{g};
                subs = obj.Selection.Groups.(G);
                for c = 1:numel(obj.Selection.Conditions)
                    cond = obj.Selection.Conditions{c};
                    [stack, n] = obj.collect_subject_metric(subs, cond, metric); % [chan x f x t x subj]
                    if isempty(stack), warning('No data for %s:%s', G, cond); continue; end
                    ga = mean(stack, 4);
                    obj.Results.GA_TFD.(G).(cond).tfd    = ga;
                    obj.Results.GA_TFD.(G).(cond).n      = n;
                    obj.Results.GA_TFD.(G).(cond).metric = metric;
                    obj.Results.GA_TFD.(G).(cond).freqs  = freqs;
                    obj.Results.GA_TFD.(G).(cond).times  = times;
                end
            end
            fprintf('GA computed for metric "%s".\n', metric);
        end

        % ---------------- Contrasts ----------------
        function obj = define_contrast(obj, name, pos_term, neg_term)
            % DEFINE_CONTRAST  Store contrast terms for later plotting/statistics.
            % pos_term/neg_term are {GroupName, ConditionName}
            obj.Results.Contrasts.(name).positive_term = pos_term;
            obj.Results.Contrasts.(name).negative_term = neg_term;

            % Build GA contrast (difference of GA maps)
            [tfd_pos, n1] = obj.get_ga_tfd_term(pos_term);
            [tfd_neg, n2] = obj.get_ga_tfd_term(neg_term);
            obj.Results.Contrasts.(name).tfd = tfd_pos - tfd_neg;
            obj.Results.Contrasts.(name).n_pos = n1;
            obj.Results.Contrasts.(name).n_neg = n2;
            fprintf('Contrast "%s" defined: %s-%s.\n', name, strjoin(pos_term,':'), strjoin(neg_term,':'));
        end

        % ---------------- Visualization ----------------
        function plot_tfr(obj, target_name, varargin)
            % Plot GA TFR for each selected condition at ROI/channel
            p = inputParser;
            addRequired(p, 'target_name', @ischar);
            addParameter(p, 'group', '', @ischar);
            addParameter(p, 'condition', '', @ischar);
            addParameter(p, 'x_range', [], @isnumeric);
            addParameter(p, 'freq_range', [], @isnumeric);
            addParameter(p, 'color_range', [], @isnumeric);
            addParameter(p, 'metric', 'power', @ischar);
            addParameter(p, 'mask', [], @(x)isnumeric(x) || islogical(x));
            parse(p, target_name, varargin{:});

            if ~isfield(obj.Results, 'GA_TFD'), error('Run compute_ga_tfd() first.'); end
            [chan_idx, roi_title] = obj.get_target_indices(target_name);

            freqs = obj.Dataset.data.meta.freqs;
            times = obj.Dataset.data.meta.times;

            gnames = fieldnames(obj.Results.GA_TFD);
            if ~isempty(p.Results.group), gnames = {p.Results.group}; end

            for g = 1:numel(gnames)
                G = gnames{g};
                cnames = fieldnames(obj.Results.GA_TFD.(G));
                if ~isempty(p.Results.condition), cnames = {p.Results.condition}; end

                figure('Name', sprintf('TFR: %s, Target: %s', G, target_name));
                for i = 1:numel(cnames)
                    cond = cnames{i};
                    subplot(1, numel(cnames), i);
                    tfd = obj.Results.GA_TFD.(G).(cond).tfd;   % [chan x f x t]
                    plot_data = squeeze(mean(tfd(chan_idx,:,:), 1)); % ROI mean

                    obj.imagesc_tfr(times, freqs, plot_data, p.Results);
                    title(sprintf('%s - %s\n%s', G, cond, roi_title));
                end
            end
        end

        function plot_contrast_tfr(obj, contrast_name, target_name, varargin)
            p = inputParser;
            addRequired(p, 'contrast_name', @ischar);
            addRequired(p, 'target_name', @ischar);
            addParameter(p, 'x_range', [], @isnumeric);
            addParameter(p, 'freq_range', [], @isnumeric);
            addParameter(p, 'color_range', [], @isnumeric);
            addParameter(p, 'mask', [], @(x)isnumeric(x) || islogical(x)); % optional significance mask [f x t]
            parse(p, contrast_name, target_name, varargin{:});

            if ~isfield(obj.Results, 'Contrasts') || ~isfield(obj.Results.Contrasts, contrast_name)
                error('Contrast "%s" not found. Run define_contrast() first.', contrast_name);
            end
            [chan_idx, roi_title] = obj.get_target_indices(target_name);

            freqs = obj.Dataset.data.meta.freqs;
            times = obj.Dataset.data.meta.times;

            tfd = obj.Results.Contrasts.(contrast_name).tfd; % [chan x f x t]
            plot_data = squeeze(mean(tfd(chan_idx,:,:), 1));

            figure('Name', sprintf('Contrast TFR: %s, %s', contrast_name, target_name));
            obj.imagesc_tfr(times, freqs, plot_data, p.Results);
            title(sprintf('Contrast: %s\n%s', strrep(contrast_name,'_',' '), roi_title));
        end

        function plot_band_timecourse(obj, roi_name, band_name, condition, group, varargin)
            % Mean±CI time course of band power in an ROI for a group/condition
            p = inputParser;
            addParameter(p, 'x_range', [], @isnumeric);
            addParameter(p, 'ci', 'sem', @(s) any(strcmpi(s,{'sem','ci95','none'})));
            parse(p, varargin{:});
            ci_mode = lower(p.Results.ci);

            freqs = obj.Dataset.data.meta.freqs;
            times = obj.Dataset.data.meta.times;
            roi = obj.Selection.ROIs.(roi_name);
            fband = obj.Selection.FreqBands.(band_name);
            [roi_idx, ~] = obj.get_target_indices(roi_name);
            fmask = freqs >= fband(1) & freqs <= fband(2);

            subs = obj.Selection.Groups.(group);
            [stack, ~] = obj.collect_subject_metric(subs, condition, 'power'); % c f t subj
            if isempty(stack), error('No data for %s/%s', group, condition); end

            % ROI+band average per subject → [t x subj]
            roi_avg = squeeze(mean(stack(roi_idx,:,:,:), 1));     % [f x t x subj]
            band_avg = squeeze(mean(roi_avg(fmask,:,:), 1));      % [t x subj]

            mu = mean(band_avg, 2);                % [t]
            switch ci_mode
                case 'sem', spread = std(band_avg,0,2) ./ sqrt(size(band_avg,2));
                case 'ci95', spread = 1.96 * std(band_avg,0,2) ./ sqrt(size(band_avg,2));
                otherwise, spread = zeros(size(mu));
            end

            figure('Name', sprintf('Band Timecourse: %s / %s / %s / %s', roi_name, band_name, condition, group));
            hold on; grid on;
            plot(times, mu, 'LineWidth', 2);
            if ~strcmp(ci_mode,'none')
                yl1 = mu - spread; yl2 = mu + spread;
                fill([times fliplr(times)], [yl1' fliplr(yl2')], [0.5 0.5 0.5], 'FaceAlpha', 0.2, 'EdgeColor','none');
            end
            if ~isempty(p.Results.x_range), xlim(p.Results.x_range); end
            xlabel('Time (ms)'); ylabel(sprintf('%s power', band_name));
            title(sprintf('%s ROI, %s band — %s (%s)', roi_name, band_name, condition, group));
        end

        function plot_topomap_band(obj, band_name, time_win, condition, group, varargin)
            % Average over freq band & time window → scalp map
            % Requires EEGLAB topoplot on path.
            p = inputParser;
            addParameter(p, 'diffmap', [], @ischar); % optional other condition name to subtract (within same group)
            parse(p, varargin{:});

            freqs = obj.Dataset.data.meta.freqs;
            times = obj.Dataset.data.meta.times;
            tmask = times >= time_win(1) & times <= time_win(2);
            fband = obj.Selection.FreqBands.(band_name);
            fmask = freqs >= fband(1) & freqs <= fband(2);

            G = group;
            subs = obj.Selection.Groups.(G);

            [stack1, ~] = obj.collect_subject_metric(subs, condition, 'power'); % [c f t subj]
            if isempty(stack1), error('No data for %s/%s', G, condition); end
            m1 = squeeze(mean(mean(stack1(:,fmask,tmask,:), 3), 2)); % [c x subj]
            map = mean(m1, 2);                                       % [c]

            if ~isempty(p.Results.diffmap)
                [stack2, ~] = obj.collect_subject_metric(subs, p.Results.diffmap, 'power');
                if isempty(stack2), error('No data for %s/%s', G, p.Results.diffmap); end
                m2 = squeeze(mean(mean(stack2(:,fmask,tmask,:), 3), 2));
                map = mean(m1 - m2, 2);
            end

            figure('Name', sprintf('Topomap: %s [%g,%g] ms %s (%s)', band_name, time_win(1), time_win(2), condition, G));
            topoplot(map, obj.Dataset.chanlocs, 'maplimits','maxmin'); colorbar;
            title(sprintf('%s band, %g-%g ms — %s (%s)', band_name, time_win(1), time_win(2), condition, G));
        end

        % ---------------- Statistics ----------------
        function obj = compute_band_stats(obj, contrast_name, roi_name, band_name, varargin)
            % ROI×Band t-test across subjects (paired/unpaired) with FDR
            % Stores Results.Contrasts.(name).Stats.band(roi,band)
            p = inputParser;
            addParameter(p, 'paired', false, @islogical);
            addParameter(p, 'alpha', 0.05, @isnumeric);
            addParameter(p, 'time_window', [], @isnumeric); % optional [t1 t2] for collapsing over time
            parse(p, varargin{:});
            paired = p.Results.paired; alpha = p.Results.alpha; tw = p.Results.time_window;

            if ~isfield(obj.Results, 'Contrasts') || ~isfield(obj.Results.Contrasts, contrast_name)
                error('Contrast "%s" not found.', contrast_name);
            end

            [chan_idx, ~] = obj.get_target_indices(roi_name);
            fband = obj.Selection.FreqBands.(band_name);
            freqs = obj.Dataset.data.meta.freqs;
            times = obj.Dataset.data.meta.times;
            fmask = freqs >= fband(1) & freqs <= fband(2);
            if isempty(tw), tmask = true(size(times)); else, tmask = times >= tw(1) & times <= tw(2); end

            def = obj.Results.Contrasts.(contrast_name);
            pos_subs = obj.Selection.Groups.(def.positive_term{1});
            neg_subs = obj.Selection.Groups.(def.negative_term{1});
            cpos = def.positive_term{2}; cneg = def.negative_term{2};

            [Xpos, ~] = obj.collect_subject_metric(pos_subs, cpos, 'power'); % [c f t subj]
            [Xneg, ~] = obj.collect_subject_metric(neg_subs, cneg, 'power');

            % ROI+band (and optional time) collapse → vector per subject
            xp = squeeze(mean(mean(mean(Xpos(chan_idx,fmask,tmask,:),1),2),3)); % [subj_pos]
            xn = squeeze(mean(mean(mean(Xneg(chan_idx,fmask,tmask,:),1),2),3)); % [subj_neg]

            % t-test
            if paired
                if numel(xp) ~= numel(xn), error('Paired test requires same #subjects.'); end
                [~, pval, ~, stats] = ttest(xp, xn);
            else
                [~, pval, ~, stats] = ttest2(xp, xn);
            end
            eff = compute_cohens_d(xp, xn, paired);

            % Store
            S = struct('roi',roi_name,'band',band_name,'paired',paired,'alpha',alpha,...
                       'n_pos',numel(xp),'n_neg',numel(xn),'t',stats.tstat,'p',pval,'d',eff,...
                       'pos_mean',mean(xp),'neg_mean',mean(xn),'time_window',tw);
            obj.Results.Contrasts.(contrast_name).Stats.band.(roi_name).(band_name) = S;
            fprintf('Band stats (%s, %s@%s): t=%.3f, p=%.3g, d=%.2f\n', contrast_name, band_name, roi_name, S.t, S.p, S.d);
        end

        function obj = compute_tfce_stats(obj, varargin)
            % TFCE hook for full TFR maps (ROI-averaged or whole scalp)
            p = inputParser;
            addParameter(p, 'contrast', '', @ischar);
            addParameter(p, 'tfce_func', [], @(f)isa(f,'function_handle'));
            addParameter(p, 'roi', '', @ischar);     % optional ROI (averages channels first)
            addParameter(p, 'n_perm', 2000, @isnumeric);
            addParameter(p, 'alpha', 0.05, @isnumeric);
            parse(p, varargin{:});

            if isempty(p.Results.contrast) || ~isfield(obj.Results.Contrasts, p.Results.contrast)
                error('Specify a valid contrast name.');
            end
            if isempty(p.Results.tfce_func), error('Provide a TFCE function handle.'); end

            def = obj.Results.Contrasts.(p.Results.contrast);
            pos_subs = obj.Selection.Groups.(def.positive_term{1});
            neg_subs = obj.Selection.Groups.(def.negative_term{1});
            cpos = def.positive_term{2}; cneg = def.negative_term{2};

            [Xpos, ~] = obj.collect_subject_metric(pos_subs, cpos, 'power'); % [c f t subj]
            [Xneg, ~] = obj.collect_subject_metric(neg_subs, cneg, 'power');

            if ~isempty(p.Results.roi)
                [chan_idx, ~] = obj.get_target_indices(p.Results.roi);
                Xpos = squeeze(mean(Xpos(chan_idx,:,:,:), 1)); % [f x t x subj]
                Xneg = squeeze(mean(Xneg(chan_idx,:,:,:), 1));
            else
                % Optionally average over channels for TFCE function requiring 3D [f x t x subj]
                Xpos = squeeze(mean(Xpos, 1));
                Xneg = squeeze(mean(Xneg, 1));
            end

            is_paired = isequal(pos_subs, neg_subs);
            if is_paired
                data = Xpos - Xneg; % [f x t x subj]
                [p_vals, clusters, cluster_p, t_map] = feval(p.Results.tfce_func, data, 'n_perm', p.Results.n_perm, 'alpha', p.Results.alpha);
            else
                [p_vals, clusters, cluster_p, t_map] = feval(p.Results.tfce_func, Xpos, Xneg, 'n_perm', p.Results.n_perm, 'alpha', p.Results.alpha);
            end

            stats = struct('p_vals',p_vals,'clusters',clusters,'cluster_p',cluster_p,'t_map',t_map,...
                           'alpha',p.Results.alpha,'roi',p.Results.roi);
            obj.Results.Contrasts.(p.Results.contrast).Stats_TFCE = stats;
            fprintf('TFCE done: %d clusters under alpha=%.3g\n', sum(cluster_p < p.Results.alpha), p.Results.alpha);
        end

        % ---------------- Features → table ----------------
        function T = extract_features(obj, varargin)
            % Extract subject-level ROI×band×window features into a table.
            % Options:
            %   'roi'      ROI name (required)
            %   'band'     band name (required)
            %   'window'   time window name (required)
            %   'metric'   'power'|'itc'|'evoked_power'|'induced_power' (default 'power')
            %   'per_subject' true/false (default true). If false, returns GA features.
            %   'metrics'  cellstr from {'mean','peak','auc'} (default {'mean'})
            p = inputParser;
            addParameter(p, 'roi', '', @ischar);
            addParameter(p, 'band', '', @ischar);
            addParameter(p, 'window', '', @ischar);
            addParameter(p, 'metric', 'power', @ischar);
            addParameter(p, 'per_subject', true, @islogical);
            addParameter(p, 'metrics', {'mean'}, @iscell);
            parse(p, varargin{:});

            if isempty(p.Results.roi) || isempty(p.Results.band) || isempty(p.Results.window)
                error('Specify roi, band, and window.');
            end

            [chan_idx, ~] = obj.get_target_indices(p.Results.roi);
            fband = obj.Selection.FreqBands.(p.Results.band);
            twin  = obj.Selection.TimeWindows.(p.Results.window);
            freqs = obj.Dataset.data.meta.freqs;  fmask = freqs >= fband(1) & freqs <= fband(2);
            times = obj.Dataset.data.meta.times;  tmask = times >= twin(1) & times <= twin(2);

            if p.Results.per_subject
                gnames = fieldnames(obj.Selection.Groups);
                rows = {};
                for g = 1:numel(gnames)
                    G = gnames{g};
                    subs = obj.Selection.Groups.(G);
                    for c = 1:numel(obj.Selection.Conditions)
                        cond = obj.Selection.Conditions{c};
                        [stack, ~] = obj.collect_subject_metric(subs, cond, p.Results.metric); % [c f t subj]
                        if isempty(stack), continue; end
                        roiX = squeeze(mean(stack(chan_idx,:,:,:), 1));     % [f x t x subj]
                        bandX = squeeze(mean(roiX(fmask,:,:), 1));          % [t x subj]
                        winX = bandX(tmask,:);                               % [tw x subj]
                        % per subject
                        for s = 1:numel(subs)
                            feats = compute_feats(winX(:,s), times(tmask), freqs(fmask), p.Results.metrics);
                            rows(end+1,:) = {G, subs{s}, cond, p.Results.roi, p.Results.band, p.Results.window, feats.mean, feats.peak_time, feats.peak_amp, feats.auc}; %#ok<AGROW>
                        end
                    end
                end
                T = cell2table(rows, 'VariableNames', {'Group','Subject','Condition','ROI','Band','Window','Mean','PeakTime','PeakAmp','AUC'});
            else
                if ~isfield(obj.Results, 'GA_TFD'), obj = obj.compute_ga_tfd('metric', p.Results.metric); end
                gnames = fieldnames(obj.Results.GA_TFD);
                rows = {};
                for g = 1:numel(gnames)
                    G = gnames{g};
                    for c = 1:numel(obj.Selection.Conditions)
                        cond = obj.Selection.Conditions{c};
                        if ~isfield(obj.Results.GA_TFD.(G), cond), continue; end
                        ga = obj.Results.GA_TFD.(G).(cond).tfd;             % [c f t]
                        roiX = squeeze(mean(ga(chan_idx,:,:), 1));          % [f x t]
                        bandX = squeeze(mean(roiX(fmask,:), 1));            % [t]
                        winX = bandX(tmask);                                 % [tw]
                        feats = compute_feats(winX(:), times(tmask), freqs(fmask), p.Results.metrics);
                        rows(end+1,:) = {G, 'GA', cond, p.Results.roi, p.Results.band, p.Results.window, feats.mean, feats.peak_time, feats.peak_amp, feats.auc}; %#ok<AGROW>
                    end
                end
                T = cell2table(rows, 'VariableNames', {'Group','Subject','Condition','ROI','Band','Window','Mean','PeakTime','PeakAmp','AUC'});
            end
        end
    end

    % ---------------- Private helpers ----------------
    methods (Access=private)
        function imagesc_tfr(obj, times, freqs, data_ft, opts)
            imagesc(times, freqs, data_ft); axis xy;
            xlabel('Time (ms)'); ylabel('Frequency (Hz)'); colorbar;
            if ~isempty(opts.x_range), xlim(opts.x_range); end
            if ~isempty(opts.freq_range), ylim(opts.freq_range); end
            if ~isempty(opts.color_range), caxis(opts.color_range); end
            if ~isempty(opts.mask)
                hold on;
                M = logical(opts.mask);
                [r,c] = find(M);
                if ~isempty(r)
                    contour(times, freqs, M, [1 1], 'LineColor','k','LineWidth',1.2);
                end
            end
        end

        function [valid, missing] = validate_subjects(obj, subject_ids)
            is_member = ismember(subject_ids, obj.Dataset.subjects);
            valid = subject_ids(is_member);
            missing = subject_ids(~is_member);
        end

        function [valid, missing] = validate_conditions(obj, condition_names)
            is_member = ismember(condition_names, obj.Dataset.conditions);
            valid = condition_names(is_member);
            missing = condition_names(~is_member);
        end

        function [valid, missing] = validate_channels(obj, channel_labels)
            dataset_channels = {obj.Dataset.chanlocs.labels};
            is_member = ismember(channel_labels, dataset_channels);
            valid = channel_labels(is_member);
            missing = channel_labels(~is_member);
        end

        function [chan_indices, title_str] = get_target_indices(obj, target_name)
            if isfield(obj.Selection.ROIs, target_name)
                labels = obj.Selection.ROIs.(target_name);
                dataset_channels = {obj.Dataset.chanlocs.labels};
                chan_indices = find(ismember(dataset_channels, labels));
                title_str = sprintf('ROI: %s', target_name);
            else
                dataset_channels = {obj.Dataset.chanlocs.labels};
                idx = find(strcmp(dataset_channels, target_name), 1);
                if isempty(idx), error('Channel "%s" not found.', target_name); end
                chan_indices = idx;
                title_str = sprintf('Channel: %s', target_name);
            end
        end

        function [stack, n] = collect_subject_metric(obj, subject_ids, condition_name, metric)
            % Returns [chan x f x t x subj]
            stack = [];
            n = 0;
            for i = 1:numel(subject_ids)
                sub_field = obj.subject_field(subject_ids{i});
                if ~isfield(obj.Dataset.data, sub_field) || ~isfield(obj.Dataset.data.(sub_field), condition_name)
                    warning('Missing %s/%s', sub_field, condition_name); continue;
                end
                S = obj.Dataset.data.(sub_field).(condition_name);
                if ~isfield(S, metric)
                    warning('Metric "%s" missing for %s/%s', metric, sub_field, condition_name); continue;
                end
                A = S.(metric); % [c f t] or [c f t x trials]
                if ndims(A) == 4
                    A = mean(A, 4); % average trials for subject-level metric
                end
                if isempty(stack), stack = zeros([size(A) numel(subject_ids)]); end
                stack(:,:,:,i) = A;
                n = n + 1;
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

        function [tfd_data, n] = get_ga_tfd_term(obj, term)
            if numel(term) ~= 2, error('Term must be {GroupName, ConditionName}.'); end
            G = term{1}; C = term{2};
            if ~isfield(obj.Results.GA_TFD, G) || ~isfield(obj.Results.GA_TFD.(G), C)
                % lazily compute GA with default metric
                obj = obj.compute_ga_tfd();
            end
            if ~isfield(obj.Results.GA_TFD, G) || ~isfield(obj.Results.GA_TFD.(G), C)
                error('GA TFD for %s:%s not found.', G, C);
            end
            tfd_data = obj.Results.GA_TFD.(G).(C).tfd;
            n = obj.Results.GA_TFD.(G).(C).n;
        end
    end
end

% --------- Local stat/feature helpers (outside class) ----------
function d = compute_cohens_d(x1, x2, paired)
if paired
    d = (mean(x1 - x2)) / std(x1 - x2);
else
    n1 = numel(x1); n2 = numel(x2);
    s_pooled = sqrt(((n1-1)*var(x1) + (n2-1)*var(x2)) / (n1+n2-2));
    d = (mean(x1) - mean(x2)) / s_pooled;
end
end

function feats = compute_feats(y, t_ms, ~, metrics)
feats.mean = NaN; feats.peak_time = NaN; feats.peak_amp = NaN; feats.auc = NaN;
if any(strcmpi(metrics,'mean')), feats.mean = mean(y); end
if any(strcmpi(metrics,'peak'))
    [mx, ix] = max(y); feats.peak_amp = mx; feats.peak_time = t_ms(ix);
end
if any(strcmpi(metrics,'auc'))
    feats.auc = trapz(t_ms, y);
end
end
