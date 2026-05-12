function state = tf_band_stats(state, args, ~)
    % Args: contrast, roi, band, alpha, time_window (opt)
    if ~isfield(args, 'alpha'), args.alpha = 0.05; end
    if ~isfield(args, 'time_window'), args.time_window = []; end

    if ~exist('ttest', 'file')
        error('This function requires the Statistics and Machine Learning Toolbox.');
    end

    cname = args.contrast;
    state_check(state, 'Contrasts');
    if ~isfield(state.Results.Contrasts, cname), error('Contrast not found'); end
    if ~isfield(state.Selection.FreqBands, args.band)
        error('Band "%s" not found. Define it first.', args.band);
    end

    def = state.Results.Contrasts.(cname);
    info = state_get_tf_contrast_arrays(state, def);
    [ch_idx, ~] = state_get_indices(state, args.roi);
    fband = state.Selection.FreqBands.(args.band);
    [freqs, times] = state_get_tf_axes(state, {}, '', def);

    fmask = freqs >= fband(1) & freqs <= fband(2);
    if ~any(fmask)
        error('No frequencies in band "%s" [%g %g] Hz.', args.band, fband(1), fband(2));
    end
    if ~isempty(args.time_window)
        tmask = times >= args.time_window(1) & times <= args.time_window(2);
    else
        tmask = true(size(times));
    end
    if ~any(tmask)
        error('No TF time points inside requested time_window [%g %g] ms.', args.time_window(1), args.time_window(2));
    end

    vp = reduce_band_values(info.X1, ch_idx, fmask, tmask);

    switch info.stat_design
        case 'onesample'
            vn = zeros(size(vp));
            [~, p, ~, stats] = ttest(vp);
        case 'paired'
            vn = reduce_band_values(info.X2, ch_idx, fmask, tmask);
            if numel(vp) ~= numel(vn), error('Paired test requires equal N'); end
            [~, p, ~, stats] = ttest(vp, vn);
        case 'two-sample'
            vn = reduce_band_values(info.X2, ch_idx, fmask, tmask);
            [~, p, ~, stats] = ttest2(vp, vn);
        otherwise
            error('Unsupported TF contrast stat design "%s".', info.stat_design);
    end
    d = compute_cohens_d(vp, vn, info.stat_design);

    is_paired_summary = strcmpi(info.stat_design, 'paired') || strcmpi(info.contrast_design, 'within');
    S = struct('roi', args.roi, 'band', args.band, 'paired', is_paired_summary, ...
        'design', info.contrast_design, ...
        'stat_design', info.stat_design, 'metric', info.metric, 'alpha', args.alpha, ...
        'n_pos', numel(vp), 'n_neg', numel(vn), 't', stats.tstat, 'p', p, 'd', d, ...
        'pos_mean', mean(vp), 'neg_mean', mean(vn), 'time_window', args.time_window);
    state.Results.Contrasts.(cname).Stats.band.(args.roi).(args.band) = S;

    fprintf('Band stats (%s, %s@%s, metric=%s): t=%.3f, p=%.3g, d=%.2f\n', ...
        cname, args.band, args.roi, S.metric, S.t, S.p, S.d);
end

function values = reduce_band_values(X, ch_idx, fmask, tmask)
    values = squeeze(mean(mean(mean(X(ch_idx, fmask, tmask, :), 1), 2), 3));
    values = values(:);
end

function d = compute_cohens_d(xp, xn, stat_design)
    switch stat_design
        case 'onesample'
            sd = std(xp);
            if sd == 0
                d = sign(mean(xp)) * Inf;
            else
                d = mean(xp) / sd;
            end
        case 'paired'
            diffx = xp - xn;
            sd = std(diffx);
            if sd == 0
                d = sign(mean(diffx)) * Inf;
            else
                d = mean(diffx) / sd;
            end
        otherwise
            s_pool = sqrt(((numel(xp)-1)*var(xp) + (numel(xn)-1)*var(xn)) / (numel(xp)+numel(xn)-2));
            if s_pool == 0
                d = sign(mean(xp) - mean(xn)) * Inf;
            else
                d = (mean(xp) - mean(xn)) / s_pool;
            end
    end
end
