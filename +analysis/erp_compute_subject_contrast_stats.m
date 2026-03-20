function state = erp_compute_subject_contrast_stats(state, args, ~)
%ERP_COMPUTE_SUBJECT_CONTRAST_STATS One-sample stats for subject-level ERP contrasts.
% Default: full ERP epoch. time_window is an explicit override for stats.
% Args:
%   contrast, roi, alpha, mcc, time_window

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

    state_check(state, 'SubjectContrasts');
    cname = args.contrast;
    if isempty(cname) || ~isfield(state.Results.SubjectContrasts, cname)
        error('Specify a valid subject contrast name.');
    end
    C = state.Results.SubjectContrasts.(cname);
    if ~isfield(C, 'erps') || isempty(C.erps)
        error('Subject contrast "%s" has no ERP data.', cname);
    end

    ver = analysis.get_version();
    fprintf('Computing subject contrast stats for "%s"... [EEGflow v%s]\n', cname, ver);

    diff_data = C.erps; % [chan x time x subj]
    data_dim = 3;
    if ~isempty(args.roi)
        if ~isfield(state.Selection, 'ROIs') || ~isfield(state.Selection.ROIs, args.roi)
            error('ROI "%s" not found. Define it first.', args.roi);
        end
        [chan_idx, ~] = state_get_indices(state, args.roi);
        diff_data = squeeze(mean(diff_data(chan_idx, :, :), 1));
        data_dim = 2;
        fprintf('Computing stats on ROI "%s" (%d channels).\n', args.roi, numel(chan_idx));
    end

    if size(diff_data, data_dim) < 2
        error('At least 2 subjects are required for one-sample stats.');
    end

    [~, p, ~, stats] = ttest(diff_data, 0, 'dim', data_dim);
    t = stats.tstat;
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

    if strcmpi(args.mcc, 'fdr')
        if ~exist('mafdr', 'file')
            error('FDR correction requires mafdr (Statistics and Machine Learning Toolbox).');
        end
        pvec = p(:);
        nan_mask = isnan(pvec);
        p_nonan = pvec(~nan_mask);
        p_corrected = nan(size(pvec));
        if ~isempty(p_nonan)
            p_corrected(~nan_mask) = mafdr(p_nonan, 'BHFDR', true);
        end
        p_corrected = reshape(p_corrected, size(p));
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

    S = struct();
    S.p = full_p;
    S.p_corrected = full_p_corrected;
    S.t = full_t;
    S.h = full_h;
    S.sig_segments = sig_segments;
    S.sig_clusters = sig_segments; % backward-compatible alias
    S.alpha = args.alpha;
    S.mcc = args.mcc;
    S.time_window = args.time_window;
    S.roi = args.roi;
    S.n_subjects = size(C.erps, 3);
    state.Results.SubjectContrasts.(cname).Stats = S;

    fprintf('Done. Found %d significant points.\n', sum(h(:)));
end
