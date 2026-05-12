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
    if ~isfield(args, 'n_perm'), args.n_perm = 1000; end
    if ~isfield(args, 'tail'), args.tail = 'two'; end
    if ~(strcmpi(args.mcc, 'none') || strcmpi(args.mcc, 'fdr') || strcmpi(args.mcc, 'cluster'))
        error('mcc must be "none", "fdr", or "cluster".');
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
    if ~isempty(args.roi)
        if ~isfield(state.Selection, 'ROIs') || ~isfield(state.Selection.ROIs, args.roi)
            error('ROI "%s" not found. Define it first.', args.roi);
        end
        [chan_idx, ~] = state_get_indices(state, args.roi);
        diff_data = mean(diff_data(chan_idx, :, :), 1);
        fprintf('Computing stats on ROI "%s" (%d channels).\n', args.roi, numel(chan_idx));
    end

    if size(diff_data, 3) < 2
        error('At least 2 subjects are required for one-sample stats.');
    end

    S = erp_waveform_stats(diff_data, [], 'onesample', state.Dataset.times, args);

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

    S.roi = args.roi;
    S.n_subjects = size(C.erps, 3);
    S.subjects_included = C.subjects;
    state.Results.SubjectContrasts.(cname).Stats = S;

    fprintf('Done. Found %d significant points.\n', sum(S.h(:)));
end
