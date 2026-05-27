function state = tf_extract_source_feature(state, args, meta)
%TF_EXTRACT_SOURCE_FEATURE Extract band/time features from source TF power.

    if nargin < 2 || isempty(args), args = struct(); end
    if nargin < 3, meta = struct(); end

    p = inputParser;
    p.addParameter('FeatureName', 'source_tf_feature', @(s) ischar(s) || isstring(s));
    p.addParameter('Condition', '', @(s) ischar(s) || isstring(s));
    p.addParameter('Contrast', {}, @(x) isempty(x) || iscellstr(x) || isstring(x));
    p.addParameter('FreqWindow', [], @(x) isempty(x) || (isnumeric(x) && numel(x) == 2 && x(2) > x(1)));
    p.addParameter('TimeWindow', [], @(x) isempty(x) || (isnumeric(x) && numel(x) == 2 && x(2) > x(1)));
    p.addParameter('Metric', 'mean', @(s) ischar(s) || isstring(s));
    nv = local_struct2nv(args);
    p.parse(nv{:});
    R = p.Results;
    R.FeatureName = matlab.lang.makeValidName(char(string(R.FeatureName)));
    R.Metric = lower(char(string(R.Metric)));

    if isfield(meta, 'validate_only') && meta.validate_only
        return;
    end
    if isempty(R.FreqWindow) || isempty(R.TimeWindow)
        error('analysis:tf_extract_source_feature:MissingWindow', ...
            'FreqWindow and TimeWindow are required.');
    end
    if ~isfield(state, 'tf_source') || ~isfield(state.tf_source, 'power')
        error('analysis:tf_extract_source_feature:MissingTF', ...
            'Run analysis.tf_compute_source first.');
    end

    tf = state.tf_source.power;
    contrast = string(R.Contrast);
    if numel(contrast) == 2
        a = local_condition(tf, contrast(1));
        b = local_condition(tf, contrast(2));
        value = local_metric(a, R) - local_metric(b, R);
        conditionInfo = sprintf('%s-%s', contrast(1), contrast(2));
    else
        cond = char(string(R.Condition));
        if isempty(cond)
            names = fieldnames(tf.conditions);
            if numel(names) ~= 1
                error('analysis:tf_extract_source_feature:MissingCondition', ...
                    'Specify Condition or a two-condition Contrast.');
            end
            cond = names{1};
        end
        c = local_condition(tf, cond);
        value = local_metric(c, R);
        conditionInfo = c.label;
    end

    feature = struct();
    feature.value = value(:);
    feature.label = tf.label;
    feature.level = tf.level;
    feature.freq_window = R.FreqWindow;
    feature.time_window = R.TimeWindow;
    feature.metric = R.Metric;
    feature.condition = conditionInfo;
    if isfield(tf, 'parcellation'), feature.parcellation = tf.parcellation; end

    if ~isfield(state.tf_source, 'features') || ~isstruct(state.tf_source.features)
        state.tf_source.features = struct();
    end
    state.tf_source.features.(R.FeatureName) = feature;
end

function value = local_metric(c, R)
    fmask = c.freqs >= R.FreqWindow(1) & c.freqs <= R.FreqWindow(2);
    tmask = c.times >= R.TimeWindow(1) & c.times <= R.TimeWindow(2);
    if ~any(fmask) || ~any(tmask)
        error('analysis:tf_extract_source_feature:BadWindow', ...
            'FreqWindow or TimeWindow does not overlap TF axes.');
    end
    X = c.power(:, fmask, tmask);
    switch R.Metric
        case 'mean'
            value = squeeze(mean(mean(X, 3, 'omitnan'), 2, 'omitnan'));
        case 'max'
            value = squeeze(max(max(X, [], 3, 'omitnan'), [], 2, 'omitnan'));
        case 'rms'
            value = squeeze(sqrt(mean(mean(X.^2, 3, 'omitnan'), 2, 'omitnan')));
        otherwise
            error('analysis:tf_extract_source_feature:BadMetric', ...
                'Metric must be mean, max, or rms.');
    end
end

function c = local_condition(tf, cond)
    f = matlab.lang.makeValidName(char(string(cond)));
    if ~isfield(tf.conditions, f)
        error('analysis:tf_extract_source_feature:UnknownCondition', ...
            'Condition not found: %s.', char(string(cond)));
    end
    c = tf.conditions.(f);
end

function nv = local_struct2nv(s)
    if isempty(s)
        nv = {};
        return;
    end
    f = fieldnames(s);
    nv = cell(1, 2 * numel(f));
    for i = 1:numel(f)
        nv{2*i-1} = f{i};
        nv{2*i} = s.(f{i});
    end
end
