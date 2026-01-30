function [state, T] = tf_extract_features(state, args, ~)
    % Args: roi, band, window, metric, metrics (cell), per_subject (bool)
    if ~isfield(args, 'metrics'), args.metrics = {'mean'}; end
    if ~iscell(args.metrics), args.metrics = {args.metrics}; end
    if ~isfield(args, 'per_subject'), args.per_subject = true; end
    if ~isfield(args, 'metric'), args.metric = 'power'; end

    if ~isfield(state.Selection, 'FreqBands') || ~isfield(state.Selection.FreqBands, args.band)
        error('Band "%s" not found. Define it first.', args.band);
    end
    if ~isfield(state.Selection, 'TimeWindows') || ~isfield(state.Selection.TimeWindows, args.window)
        error('Time window "%s" not found. Define it first.', args.window);
    end

    if isempty(fieldnames(state.Selection.Groups)), error('No groups defined.'); end
    if isempty(state.Selection.Conditions), error('No conditions selected.'); end

    [ch_idx, ~] = state_get_indices(state, args.roi);
    fband = state.Selection.FreqBands.(args.band);
    twin = state.Selection.TimeWindows.(args.window);
    gnames = fieldnames(state.Selection.Groups);
    subs0 = state.Selection.Groups.(gnames{1});
    [freqs, times] = resolve_tf_axes(state, subs0, state.Selection.Conditions{1});

    fmask = freqs >= fband(1) & freqs <= fband(2);
    tmask = times >= twin(1) & times <= twin(2);

    rows = {};

    if args.per_subject
        gnames = fieldnames(state.Selection.Groups);
        for g = 1:numel(gnames)
            gn = gnames{g};
            subs = state.Selection.Groups.(gn);
            for c = 1:numel(state.Selection.Conditions)
                cn = state.Selection.Conditions{c};
                [stack, ~] = state_collect_metric_tf(state, subs, cn, args.metric);
                if isempty(stack), continue; end

                roiX = squeeze(mean(stack(ch_idx, :, :, :), 1));   % [f x t x subj]
                bandX = squeeze(mean(roiX(fmask, :, :), 1));       % [t x subj]
                winX = bandX(tmask, :);                            % [tw x subj]

                for s = 1:numel(subs)
                    feats = compute_feats(winX(:, s), times(tmask), freqs(fmask), args.metrics);
                    rows(end+1, :) = {gn, subs{s}, cn, args.roi, args.band, args.window, ...
                        feats.mean, feats.peak_time, feats.peak_amp, feats.auc}; %#ok<AGROW>
                end
            end
        end
    else
        if ~isfield(state.Results, 'GA_TFD') || isempty(fieldnames(state.Results.GA_TFD))
            state = tf_compute_ga(state, struct('metric', args.metric), struct());
        end
        gnames = fieldnames(state.Results.GA_TFD);
        for g = 1:numel(gnames)
            gn = gnames{g};
            for c = 1:numel(state.Selection.Conditions)
                cn = state.Selection.Conditions{c};
                if ~isfield(state.Results.GA_TFD.(gn), cn), continue; end
                ga = state.Results.GA_TFD.(gn).(cn).tfd;           % [c f t]
                roiX = squeeze(mean(ga(ch_idx, :, :), 1));         % [f x t]
                bandX = squeeze(mean(roiX(fmask, :), 1));          % [t]
                winX = bandX(tmask);
                feats = compute_feats(winX(:), times(tmask), freqs(fmask), args.metrics);
                rows(end+1, :) = {gn, 'GA', cn, args.roi, args.band, args.window, ...
                    feats.mean, feats.peak_time, feats.peak_amp, feats.auc}; %#ok<AGROW>
            end
        end
    end

    if isempty(rows)
        T = table();
    else
        T = cell2table(rows, 'VariableNames', {'Group','Subject','Condition','ROI','Band','Window','Mean','PeakTime','PeakAmp','AUC'});
    end
    state.Results.Features.LastTable = T;
end

function feats = compute_feats(y, t_ms, ~, metrics)
    feats.mean = NaN; feats.peak_time = NaN; feats.peak_amp = NaN; feats.auc = NaN;
    if any(strcmpi(metrics, 'mean')), feats.mean = mean(y); end
    if any(strcmpi(metrics, 'peak'))
        [mx, ix] = max(y); feats.peak_amp = mx; feats.peak_time = t_ms(ix);
    end
    if any(strcmpi(metrics, 'auc'))
        feats.auc = trapz(t_ms, y);
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
