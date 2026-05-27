function state = extract_window_feature(state, args, meta)
%EXTRACT_WINDOW_FEATURE Extract parcel/source features from source ERPs.
%
% Output:
%   state.source.features.(FeatureName).value = [nSourceOrParcel x 1]
%
% Supported metrics: mean, peak_positive, peak_negative, peak_absolute,
% peak_latency, rms, t_value, cohens_d.

    if nargin < 1 || isempty(state), state = struct(); end
    if nargin < 2 || isempty(args), args = struct(); end
    if nargin < 3 || isempty(meta), meta = struct(); end

    op = 'source_extract_window_feature';
    cfg0 = state_get_config(state, op);
    params = state_merge(cfg0, args);

    p = inputParser;
    p.addParameter('LogFile', '', @(s) ischar(s) || isstring(s));
    p.addParameter('FeatureName', 'source_feature', @(s) ischar(s) || isstring(s));
    p.addParameter('TimeWindow', [], @(x) isempty(x) || (isnumeric(x) && numel(x) == 2 && x(2) > x(1)));
    p.addParameter('Metric', 'mean', @(s) ischar(s) || isstring(s));
    p.addParameter('Condition', '', @(s) ischar(s) || isstring(s));
    p.addParameter('Contrast', {}, @(x) isempty(x) || iscellstr(x) || isstring(x));

    nv = state_struct2nv(params);
    p.parse(nv{:});
    R = p.Results;
    R.FeatureName = matlab.lang.makeValidName(char(string(R.FeatureName)));
    R.Metric = lower(char(string(R.Metric)));

    if isfield(meta, 'validate_only') && meta.validate_only
        state = state_update_history(state, op, R, 'validated', struct());
        return;
    end
    if isempty(R.TimeWindow)
        error('source:extract_window_feature:MissingTimeWindow', 'TimeWindow is required.');
    end

    if ~isfield(state, 'source') || ~isfield(state.source, 'erp')
        error('source:extract_window_feature:MissingERP', 'Run source.compute_erps before extracting source window features.');
    end

    erp = state.source.erp;
    time = erp.time;
    tmask = time >= R.TimeWindow(1) & time <= R.TimeWindow(2);
    if ~any(tmask)
        error('source:extract_window_feature:BadTimeWindow', 'TimeWindow does not overlap source ERP time.');
    end

    contrast = string(R.Contrast);
    if numel(contrast) == 2
        a = local_get_condition(erp, contrast(1));
        b = local_get_condition(erp, contrast(2));
        if ismember(R.Metric, {'t_value','cohens_d'})
            value = local_contrast_stat(a, b, tmask, R.Metric);
        else
            value = local_metric(a.avg(:, tmask), erp.time(tmask), R.Metric) - ...
                local_metric(b.avg(:, tmask), erp.time(tmask), R.Metric);
        end
        conditionInfo = sprintf('%s-%s', contrast(1), contrast(2));
    else
        cond = char(string(R.Condition));
        if isempty(cond)
            names = fieldnames(erp.conditions);
            if numel(names) ~= 1
                error('source:extract_window_feature:MissingCondition', 'Specify Condition or a two-condition Contrast.');
            end
            cond = names{1};
        end
        c = local_get_condition(erp, string(cond));
        value = local_metric(c.avg(:, tmask), erp.time(tmask), R.Metric);
        conditionInfo = c.label;
    end

    feature = struct();
    feature.value = value(:);
    feature.label = erp.label;
    feature.source_pos = erp.source_pos;
    feature.level = erp.level;
    feature.unit = erp.unit;
    feature.time_window = R.TimeWindow;
    feature.metric = R.Metric;
    feature.condition = conditionInfo;
    if isfield(erp, 'parcellation'), feature.parcellation = erp.parcellation; end

    if ~isfield(state.source, 'features') || ~isstruct(state.source.features)
        state.source.features = struct();
    end
    state.source.features.(R.FeatureName) = feature;

    out = struct('feature', R.FeatureName, 'n_values', numel(value), 'condition', conditionInfo);
    log_step(state, meta, R.LogFile, sprintf('[source.extract_window_feature] %s | n=%d', R.FeatureName, numel(value)));
    state = state_update_history(state, op, R, 'success', out);
end

function c = local_get_condition(erp, cond)
    name = matlab.lang.makeValidName(char(cond));
    if ~isfield(erp.conditions, name)
        error('source:extract_window_feature:UnknownCondition', 'Condition not found: %s', char(cond));
    end
    c = erp.conditions.(name);
end

function v = local_metric(X, time, metric)
    switch metric
        case 'mean'
            v = mean(X, 2, 'omitnan');
        case 'peak_positive'
            v = max(X, [], 2, 'omitnan');
        case 'peak_negative'
            v = min(X, [], 2, 'omitnan');
        case 'peak_absolute'
            [~, idx] = max(abs(X), [], 2);
            v = nan(size(X, 1), 1);
            for i = 1:size(X, 1)
                v(i) = X(i, idx(i));
            end
        case 'peak_latency'
            [~, idx] = max(abs(X), [], 2);
            v = nan(size(X, 1), 1);
            for i = 1:size(X, 1)
                v(i) = time(idx(i));
            end
        case 'rms'
            v = sqrt(mean(X.^2, 2, 'omitnan'));
        otherwise
            error('source:extract_window_feature:BadMetric', 'Unsupported Metric=%s.', metric);
    end
end

function value = local_contrast_stat(a, b, tmask, metric)
    if ~isfield(a, 'trial') || ~isfield(b, 'trial') || isempty(a.trial) || isempty(b.trial)
        error('source:extract_window_feature:MissingTrials', ...
            'Metric=%s requires source.compute_erps with KeepTrials=true.', metric);
    end
    A = local_trial_window_values(a.trial, tmask);
    B = local_trial_window_values(b.trial, tmask);
    ma = mean(A, 2, 'omitnan');
    mb = mean(B, 2, 'omitnan');
    va = var(A, 0, 2, 'omitnan');
    vb = var(B, 0, 2, 'omitnan');
    na = sum(isfinite(A), 2);
    nb = sum(isfinite(B), 2);
    switch metric
        case 't_value'
            value = (ma - mb) ./ sqrt(va ./ na + vb ./ nb);
        case 'cohens_d'
            pooled = sqrt(((na - 1) .* va + (nb - 1) .* vb) ./ max(na + nb - 2, 1));
            value = (ma - mb) ./ pooled;
        otherwise
            error('source:extract_window_feature:BadMetric', 'Unsupported contrast statistic: %s.', metric);
    end
end

function M = local_trial_window_values(trials, tmask)
    nTrial = numel(trials);
    nSig = size(trials{1}, 1);
    M = nan(nSig, nTrial);
    for t = 1:nTrial
        M(:, t) = mean(double(trials{t}(:, tmask)), 2, 'omitnan');
    end
end
