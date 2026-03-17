function state = erp_compute_stats(state, args, ~)
    % Args: contrast, roi, alpha, mcc, time_window
    if nargin < 2, args = struct(); end
    if ~isfield(args, 'contrast'), args.contrast = ''; end
    if ~isfield(args, 'alpha'), args.alpha = 0.05; end
    if ~isfield(args, 'mcc'), args.mcc = 'none'; end
    if ~isfield(args, 'time_window'), args.time_window = []; end
    if ~isfield(args, 'roi'), args.roi = ''; end
    if ~(strcmpi(args.mcc, 'none') || strcmpi(args.mcc, 'fdr'))
        error('mcc must be "none" or "fdr".');
    end

    if ~exist('ttest', 'file')
        error('This function requires the Statistics and Machine Learning Toolbox.');
    end

    state_check(state, 'ERPs');
    cname = args.contrast;
    if isempty(cname) || ~isfield(state.Results, 'Contrasts') || ~isfield(state.Results.Contrasts, cname)
        error('Specify a valid contrast name.');
    end

    ver = analysis.get_version();
    fprintf('Computing stats for contrast "%s"... [EEGflow v%s]\n', cname, ver);

    def = state.Results.Contrasts.(cname);
    pos_group = def.positive_term{1};
    pos_cond = def.positive_term{2};
    neg_group = def.negative_term{1};
    neg_cond = def.negative_term{2};

    pos_subjects = state.Selection.Groups.(pos_group);
    neg_subjects = state.Selection.Groups.(neg_group);

    [pos_data, pos_found] = state_collect_erps(state, pos_subjects, pos_cond);
    [neg_data, neg_found] = state_collect_erps(state, neg_subjects, neg_cond);
    if isempty(pos_data) || isempty(neg_data)
        error('No ERP data found for contrast terms.');
    end

    data_dim = 3;
    if ~isempty(args.roi)
        if ~isfield(state.Selection, 'ROIs') || ~isfield(state.Selection.ROIs, args.roi)
            error('ROI "%s" not found. Define it first.', args.roi);
        end
        [chan_idx, ~] = state_get_indices(state, args.roi);
        pos_data = squeeze(mean(pos_data(chan_idx, :, :), 1));
        neg_data = squeeze(mean(neg_data(chan_idx, :, :), 1));
        data_dim = 2;
        fprintf('Computing stats on ROI "%s" (%d channels).\n', args.roi, numel(chan_idx));
    end

    is_paired = isequal(pos_subjects, neg_subjects) && strcmp(pos_group, neg_group);
    if is_paired
        [common_subs, ia, ib] = intersect(pos_found, neg_found, 'stable');
        if numel(common_subs) < numel(pos_found) || numel(common_subs) < numel(neg_found)
            warning('Unequal subjects for paired test. Using %d common subjects.', numel(common_subs));
        end
        if numel(common_subs) < 2
            error('Paired stats require at least 2 common subjects. Found %d.', numel(common_subs));
        end
        if data_dim == 3
            pos_paired = pos_data(:, :, ia);
            neg_paired = neg_data(:, :, ib);
        else
            pos_paired = pos_data(:, ia);
            neg_paired = neg_data(:, ib);
        end
        diff_data = pos_paired - neg_paired;
        [~, p, ~, stats] = ttest(diff_data, 0, 'dim', data_dim);
        t = stats.tstat;
    else
        if size(pos_data, data_dim) < 2 || size(neg_data, data_dim) < 2
            warning('Unpaired stats are being computed with <2 subjects in at least one term.');
        end
        [~, p, ~, stats] = ttest2(pos_data, neg_data, 'dim', data_dim);
        t = stats.tstat;
    end
    if data_dim == 2
        p = reshape(p, 1, []);
        t = reshape(t, 1, []);
    end

    time_indices = 1:size(state.Dataset.times, 2);
    if ~isempty(args.time_window)
        if ~isnumeric(args.time_window) || numel(args.time_window) ~= 2 || args.time_window(1) >= args.time_window(2)
            error('time_window must be [start end] in ms.');
        end
        time_indices = state.Dataset.times >= args.time_window(1) & state.Dataset.times <= args.time_window(2);
        if ~any(time_indices)
            error('time_window [%g %g] ms does not overlap dataset time range [%g %g] ms.', ...
                args.time_window(1), args.time_window(2), state.Dataset.times(1), state.Dataset.times(end));
        end
        if data_dim == 3
            p = p(:, time_indices);
            t = t(:, time_indices);
        else
            p = p(time_indices);
            t = t(time_indices);
        end
    end

    p_corrected = nan(size(p));
    if strcmpi(args.mcc, 'fdr')
        if ~exist('mafdr', 'file')
            error('FDR correction requires mafdr (Statistics and Machine Learning Toolbox).');
        end
        p_vector = p(:);
        nan_mask = isnan(p_vector);
        p_vector_nonan = p_vector(~nan_mask);
        if ~isempty(p_vector_nonan)
            p_corr_vec = mafdr(p_vector_nonan, 'BHFDR', true);
            p_corr = nan(size(p_vector));
            p_corr(~nan_mask) = p_corr_vec;
            p_corrected = reshape(p_corr, size(p));
        else
            warning('All p-values were NaN; FDR correction not applied.');
            p_corrected = p;
        end
    else
        p_corrected = p;
    end
    h = p_corrected < args.alpha;

    tvec = state.Dataset.times(time_indices);
    sig_segments = cell(size(h, 1), 1);
    any_found = false;
    for ch = 1:size(h, 1)
        segments = state_get_sig_windows(h(ch, :), tvec);
        if ~isempty(segments)
            any_found = true;
            sig_segments{ch} = segments;
            if isempty(args.roi)
                fprintf('Ch %s: %d significant segment(s).\n', state.Dataset.chanlocs(ch).labels, size(segments, 1));
            else
                fprintf('ROI %s: %d significant segment(s).\n', args.roi, size(segments, 1));
            end
        end
    end
    if ~any_found
        fprintf('No significant segments found.\n');
    end

    if ~isempty(args.roi)
        num_chans = 1;
    else
        num_chans = numel(state.Dataset.chanlocs);
    end
    full_p = nan(num_chans, numel(state.Dataset.times));
    full_t = nan(num_chans, numel(state.Dataset.times));
    full_h = false(num_chans, numel(state.Dataset.times));
    full_p_corrected = nan(num_chans, numel(state.Dataset.times));
    full_p(:, time_indices) = p;
    full_t(:, time_indices) = t;
    full_h(:, time_indices) = h;
    full_p_corrected(:, time_indices) = p_corrected;

    state.Results.Contrasts.(cname).Stats.p = full_p;
    state.Results.Contrasts.(cname).Stats.p_corrected = full_p_corrected;
    state.Results.Contrasts.(cname).Stats.t = full_t;
    state.Results.Contrasts.(cname).Stats.h = full_h;
    state.Results.Contrasts.(cname).Stats.sig_segments = sig_segments;
    state.Results.Contrasts.(cname).Stats.sig_clusters = sig_segments; % backward compatibility
    state.Results.Contrasts.(cname).Stats.alpha = args.alpha;
    state.Results.Contrasts.(cname).Stats.mcc = args.mcc;
    state.Results.Contrasts.(cname).Stats.is_paired = is_paired;
    state.Results.Contrasts.(cname).Stats.time_window = args.time_window;
    state.Results.Contrasts.(cname).Stats.roi = args.roi;
    fprintf('Done. Found %d significant points.\n', sum(h(:)));
end
