function state = tfr_band_stats(state, args, ~)
    % Args: contrast, roi, band, paired (bool), alpha, time_window (opt)
    if ~isfield(args, 'paired'), args.paired = false; end
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

    [ch_idx, ~] = state_get_indices(state, args.roi);
    fband = state.Selection.FreqBands.(args.band);
    [freqs, times] = resolve_tf_axes(state, state.Selection.Groups.(state.Results.Contrasts.(cname).positive_term{1}), ...
        state.Results.Contrasts.(cname).positive_term{2});

    fmask = freqs >= fband(1) & freqs <= fband(2);
    if ~isempty(args.time_window)
        tmask = times >= args.time_window(1) & times <= args.time_window(2);
    else
        tmask = true(size(times));
    end

    def = state.Results.Contrasts.(cname);
    subs_p = state.Selection.Groups.(def.positive_term{1});
    subs_n = state.Selection.Groups.(def.negative_term{1});

    [Xp, ~] = state_collect_metric_tfr(state, subs_p, def.positive_term{2}, 'power');
    [Xn, ~] = state_collect_metric_tfr(state, subs_n, def.negative_term{2}, 'power');
    if isempty(Xp) || isempty(Xn)
        error('No data found for contrast terms.');
    end

    vp = squeeze(mean(mean(mean(Xp(ch_idx, fmask, tmask, :), 1), 2), 3));
    vn = squeeze(mean(mean(mean(Xn(ch_idx, fmask, tmask, :), 1), 2), 3));

    if args.paired
        if numel(vp) ~= numel(vn), error('Paired test requires equal N'); end
        [~, p, ~, stats] = ttest(vp, vn);
    else
        [~, p, ~, stats] = ttest2(vp, vn);
    end
    d = compute_cohens_d(vp, vn, args.paired);

    S = struct('roi', args.roi, 'band', args.band, 'paired', args.paired, 'alpha', args.alpha, ...
        'n_pos', numel(vp), 'n_neg', numel(vn), 't', stats.tstat, 'p', p, 'd', d, ...
        'pos_mean', mean(vp), 'neg_mean', mean(vn), 'time_window', args.time_window);
    state.Results.Contrasts.(cname).Stats.band.(args.roi).(args.band) = S;

    fprintf('Band stats (%s, %s@%s): t=%.3f, p=%.3g, d=%.2f\n', cname, args.band, args.roi, S.t, S.p, S.d);
end

function d = compute_cohens_d(xp, xn, paired)
    if paired
        diffx = xp - xn;
        d = mean(diffx) / std(diffx);
    else
        s_pool = sqrt(((numel(xp)-1)*var(xp) + (numel(xn)-1)*var(xn)) / (numel(xp)+numel(xn)-2));
        d = (mean(xp) - mean(xn)) / s_pool;
    end
end

function [freqs, times] = resolve_tf_axes(state, subjects, condition)
    freqs = [];
    times = [];
    if isfield(state.Dataset.data, 'meta')
        meta = state.Dataset.data.meta;
        if isfield(meta, 'freqs'), freqs = meta.freqs; end
        if isfield(meta, 'times'), times = meta.times; end
    end
    if ~isempty(freqs) && ~isempty(times)
        return;
    end
    if isfield(state.Results, 'TF')
        for i = 1:numel(subjects)
            sfield = state_subject_field(state, subjects{i});
            if isfield(state.Results.TF, sfield) && isfield(state.Results.TF.(sfield), condition)
                entry = state.Results.TF.(sfield).(condition);
                if isfield(entry, 'freqs'), freqs = entry.freqs; end
                if isfield(entry, 'times'), times = entry.times; end
                break;
            end
        end
    end
    if isempty(freqs) || isempty(times)
        error('TF axes (freqs/times) not found in Dataset.meta or Results.TF.');
    end
end
