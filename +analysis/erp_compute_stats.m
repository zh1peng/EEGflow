function state = erp_compute_stats(state, args, ~)
    % Default: full ERP epoch. time_window is an explicit override for stats.
    % Args: contrast, roi, alpha, mcc, time_window
    if nargin < 2, args = struct(); end
    if ~isfield(args, 'contrast'), args.contrast = ''; end
    if ~isfield(args, 'alpha'), args.alpha = 0.05; end
    if ~isfield(args, 'mcc'), args.mcc = 'none'; end
    if ~isfield(args, 'time_window'), args.time_window = []; end
    if ~isfield(args, 'roi'), args.roi = ''; end
    if ~isfield(args, 'n_perm'), args.n_perm = 1000; end
    if ~isfield(args, 'tail'), args.tail = 'two'; end
    if ~(strcmpi(args.mcc, 'none') || strcmpi(args.mcc, 'fdr') || strcmpi(args.mcc, 'cluster'))
        error('mcc must be "none", "fdr", or "cluster".');
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

    if ~isempty(args.roi)
        if ~isfield(state.Selection, 'ROIs') || ~isfield(state.Selection.ROIs, args.roi)
            error('ROI "%s" not found. Define it first.', args.roi);
        end
        [chan_idx, ~] = state_get_indices(state, args.roi);
        pos_data = mean(pos_data(chan_idx, :, :), 1);
        neg_data = mean(neg_data(chan_idx, :, :), 1);
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
        X1 = pos_data(:, :, ia) - neg_data(:, :, ib);
        X2 = [];
        design = 'onesample';
        subjects_included = common_subs;
    else
        if size(pos_data, 3) < 2 || size(neg_data, 3) < 2
            warning('Unpaired stats are being computed with <2 subjects in at least one term.');
        end
        X1 = pos_data;
        X2 = neg_data;
        design = 'two-sample';
        subjects_included = unique([pos_found, neg_found], 'stable');
    end

    S = erp_waveform_stats(X1, X2, design, state.Dataset.times, args);

    any_found = false;
    for ch = 1:size(S.h, 1)
        segments = S.sig_segments{ch};
        if ~isempty(segments)
            any_found = true;
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

    S.is_paired = is_paired;
    S.roi = args.roi;
    S.subjects_positive = pos_found;
    S.subjects_negative = neg_found;
    S.subjects_included = subjects_included;
    S.subjects_excluded = setdiff(unique([pos_found, neg_found], 'stable'), subjects_included, 'stable');
    state.Results.Contrasts.(cname).Stats = S;
    fprintf('Done. Found %d significant points.\n', sum(S.h(:)));
end
