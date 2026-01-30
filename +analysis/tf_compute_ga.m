function state = tf_compute_ga(state, args, ~)
    % Args: metric (default 'power')
    if nargin < 2 || isempty(args), args = struct(); end
    if ~isfield(args, 'metric'), args.metric = 'power'; end

    state_check(state);
    if isempty(fieldnames(state.Selection.Groups)), error('No groups defined'); end
    if isempty(state.Selection.Conditions), error('No conditions selected'); end

    fprintf('Computing GA TFD (Metric: %s)...\n', args.metric);
    state.Results.GA_TFD = struct();

    groups = fieldnames(state.Selection.Groups);
    for g = 1:numel(groups)
        gn = groups{g};
        subs = state.Selection.Groups.(gn);
        for c = 1:numel(state.Selection.Conditions)
            cn = state.Selection.Conditions{c};

            [stack, n] = state_collect_metric_tf(state, subs, cn, args.metric);
            if isempty(stack)
                warning('No data for %s:%s', gn, cn);
                continue;
            end

            [freqs, times] = resolve_tf_axes(state, subs, cn);

            state.Results.GA_TFD.(gn).(cn).tfd = mean(stack, 4);
            state.Results.GA_TFD.(gn).(cn).n = n;
            state.Results.GA_TFD.(gn).(cn).metric = args.metric;
            state.Results.GA_TFD.(gn).(cn).freqs = freqs;
            state.Results.GA_TFD.(gn).(cn).times = times;
        end
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
    if isfield(state, 'Results') && isfield(state.Results, 'TF')
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
