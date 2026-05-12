function S = erp_waveform_stats(X1, X2, design, times, args)
%ERP_WAVEFORM_STATS Point-wise and cluster-corrected ERP waveform stats.
% X1/X2 are [row x time x subject]. Rows are channels or one ROI average.

    if nargin < 5, args = struct(); end
    if ~isfield(args, 'alpha'), args.alpha = 0.05; end
    if ~isfield(args, 'mcc'), args.mcc = 'none'; end
    if ~isfield(args, 'time_window'), args.time_window = []; end
    if ~isfield(args, 'n_perm'), args.n_perm = 1000; end
    if ~isfield(args, 'tail'), args.tail = 'two'; end

    X1 = ensure_3d(X1);
    if ~isempty(X2), X2 = ensure_3d(X2); end
    times = reshape(times, 1, []);
    design = lower(char(design));
    mcc = lower(char(args.mcc));
    tail = lower(char(args.tail));

    if ~ismember(mcc, {'none', 'fdr', 'cluster'})
        error('mcc must be "none", "fdr", or "cluster".');
    end
    if ~ismember(design, {'onesample', 'two-sample'})
        error('Unsupported ERP stats design "%s".', design);
    end
    if ~ismember(tail, {'two', 'pos', 'neg'})
        error('tail must be "two", "pos", or "neg".');
    end
    if size(X1, 2) ~= numel(times)
        error('X1 time dimension (%d) must match times length (%d).', size(X1, 2), numel(times));
    end
    if strcmp(design, 'two-sample') && (isempty(X2) || size(X2, 2) ~= numel(times))
        error('X2 is required for two-sample ERP stats and must match the time axis.');
    end

    time_mask = true(1, numel(times));
    if ~isempty(args.time_window)
        if ~isnumeric(args.time_window) || numel(args.time_window) ~= 2 || args.time_window(1) >= args.time_window(2)
            error('time_window must be [start end] in ms.');
        end
        time_mask = times >= args.time_window(1) & times <= args.time_window(2);
        if ~any(time_mask)
            error('time_window [%g %g] ms does not overlap dataset time range [%g %g] ms.', ...
                args.time_window(1), args.time_window(2), times(1), times(end));
        end
    end

    X1w = X1(:, time_mask, :);
    if isempty(X2)
        X2w = [];
    else
        X2w = X2(:, time_mask, :);
    end

    [t, p] = compute_pointwise_t(X1w, X2w, design);
    p_corrected = p;
    clusters = cell(size(p, 1), 1);

    switch mcc
        case 'none'
            h = p < args.alpha;
        case 'fdr'
            if ~exist('mafdr', 'file')
                error('FDR correction requires mafdr (Statistics and Machine Learning Toolbox).');
            end
            p_corrected = fdr_correct(p);
            h = p_corrected < args.alpha;
        case 'cluster'
            if ~exist('tinv', 'file')
                error('Cluster correction requires tinv (Statistics and Machine Learning Toolbox).');
            end
            [h, p_corrected, clusters] = cluster_correct(X1w, X2w, design, t, times(time_mask), ...
                args.alpha, args.n_perm, tail, args);
    end

    n_rows = size(X1, 1);
    n_times = numel(times);
    full_p = nan(n_rows, n_times);
    full_t = nan(n_rows, n_times);
    full_h = false(n_rows, n_times);
    full_p_corrected = nan(n_rows, n_times);
    full_p(:, time_mask) = p;
    full_t(:, time_mask) = t;
    full_h(:, time_mask) = h;
    full_p_corrected(:, time_mask) = p_corrected;

    sig_segments = cell(n_rows, 1);
    for r = 1:n_rows
        sig_segments{r} = state_get_sig_windows(full_h(r, :), times);
    end

    S = struct();
    S.p = full_p;
    S.p_corrected = full_p_corrected;
    S.t = full_t;
    S.h = full_h;
    S.sig_segments = sig_segments;
    S.sig_clusters = sig_segments;
    S.clusters = clusters;
    S.alpha = args.alpha;
    S.mcc = mcc;
    S.design = design;
    S.time_window = args.time_window;
    S.n_perm = args.n_perm;
    S.tail = tail;
    S.n_positive = size(X1, 3);
    if isempty(X2)
        S.n_negative = 0;
    else
        S.n_negative = size(X2, 3);
    end
end

function X = ensure_3d(X)
    if ndims(X) == 2
        X = reshape(X, 1, size(X, 1), size(X, 2));
    end
    if ndims(X) ~= 3
        error('ERP stats data must be [row x time x subject].');
    end
end

function [t, p] = compute_pointwise_t(X1, X2, design)
    n_rows = size(X1, 1);
    n_times = size(X1, 2);
    switch design
        case 'onesample'
            [~, p_raw, ~, stats] = ttest(X1, 0, 'dim', 3);
        case 'two-sample'
            [~, p_raw, ~, stats] = ttest2(X1, X2, 'dim', 3);
    end
    p = reshape(p_raw, n_rows, n_times);
    t = reshape(stats.tstat, n_rows, n_times);
end

function p_corrected = fdr_correct(p)
    pvec = p(:);
    nan_mask = isnan(pvec);
    p_corrected = nan(size(pvec));
    if any(~nan_mask)
        p_corrected(~nan_mask) = mafdr(pvec(~nan_mask), 'BHFDR', true);
    end
    p_corrected = reshape(p_corrected, size(p));
end

function [h, p_corrected, clusters_by_row] = cluster_correct(X1, X2, design, t_obs, times, alpha, n_perm, tail, args)
    n_rows = size(t_obs, 1);
    h = false(size(t_obs));
    p_corrected = ones(size(t_obs));
    clusters_by_row = cell(n_rows, 1);

    old_rng = [];
    if isfield(args, 'seed') && ~isempty(args.seed)
        old_rng = rng();
        rng(args.seed);
    end

    max_null = zeros(max(1, n_perm), n_rows);
    for p = 1:max(1, n_perm)
        [Xp, Xn] = permute_data(X1, X2, design);
        [t_perm, ~] = compute_pointwise_t(Xp, Xn, design);
        for r = 1:n_rows
            perm_clusters = find_clusters(t_perm(r, :), threshold_mask(t_perm(r, :), alpha, tail, df_for_design(Xp, Xn, design)));
            if ~isempty(perm_clusters)
                max_null(p, r) = max([perm_clusters.mass]);
            end
        end
    end

    df = df_for_design(X1, X2, design);
    for r = 1:n_rows
        obs_clusters = find_clusters(t_obs(r, :), threshold_mask(t_obs(r, :), alpha, tail, df));
        for c = 1:numel(obs_clusters)
            pval = (1 + sum(max_null(:, r) >= obs_clusters(c).mass)) / (size(max_null, 1) + 1);
            obs_clusters(c).p = pval;
            obs_clusters(c).start_time = times(obs_clusters(c).indices(1));
            obs_clusters(c).end_time = times(obs_clusters(c).indices(end));
            p_corrected(r, obs_clusters(c).indices) = min(p_corrected(r, obs_clusters(c).indices), pval);
            if pval < alpha
                h(r, obs_clusters(c).indices) = true;
            end
        end
        clusters_by_row{r} = obs_clusters;
    end

    if ~isempty(old_rng)
        rng(old_rng);
    end
end

function mask = threshold_mask(trow, alpha, tail, df)
    switch tail
        case 'two'
            tcrit = tinv(1 - alpha / 2, df);
            mask = abs(trow) >= tcrit;
        case 'pos'
            tcrit = tinv(1 - alpha, df);
            mask = trow >= tcrit;
        case 'neg'
            tcrit = tinv(1 - alpha, df);
            mask = trow <= -tcrit;
    end
end

function df = df_for_design(X1, X2, design)
    switch design
        case 'onesample'
            df = size(X1, 3) - 1;
        case 'two-sample'
            df = size(X1, 3) + size(X2, 3) - 2;
    end
end

function clusters = find_clusters(trow, mask)
    clusters = struct('indices', {}, 'mass', {}, 'p', {}, 'start_time', {}, 'end_time', {});
    if ~any(mask), return; end
    d = diff([false, mask, false]);
    starts = find(d == 1);
    ends = find(d == -1) - 1;
    for i = 1:numel(starts)
        ix = starts(i):ends(i);
        clusters(end+1).indices = ix; %#ok<AGROW>
        clusters(end).mass = sum(abs(trow(ix)));
        clusters(end).p = NaN;
        clusters(end).start_time = NaN;
        clusters(end).end_time = NaN;
    end
end

function [Xp, Xn] = permute_data(X1, X2, design)
    switch design
        case 'onesample'
            signs = (rand(1, size(X1, 3)) > 0.5) * 2 - 1;
            Xp = X1 .* reshape(signs, 1, 1, []);
            Xn = [];
        case 'two-sample'
            allX = cat(3, X1, X2);
            n1 = size(X1, 3);
            idx = randperm(size(allX, 3));
            Xp = allX(:, :, idx(1:n1));
            Xn = allX(:, :, idx(n1+1:end));
    end
end
