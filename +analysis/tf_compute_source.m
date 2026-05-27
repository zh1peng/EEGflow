function state = tf_compute_source(state, args, meta)
%TF_COMPUTE_SOURCE Compute time-frequency power from source/parcel epochs.

    if nargin < 2 || isempty(args), args = struct(); end
    if nargin < 3, meta = struct(); end

    p = inputParser;
    p.addParameter('InputField', 'epochs', @(s) ischar(s) || isstring(s));
    p.addParameter('ConditionLabels', [], @(x) isempty(x) || iscellstr(x) || isstring(x) || isnumeric(x) || iscategorical(x));
    p.addParameter('ConditionField', '', @(s) ischar(s) || isstring(s));
    p.addParameter('Freqs', [3 30], @(x) isnumeric(x) && (numel(x) == 2 || isvector(x)));
    p.addParameter('Cycles', [3 0.5], @(x) isnumeric(x) && ~isempty(x));
    p.addParameter('TimesOut', 200, @(x) isnumeric(x) && isscalar(x) && x > 0);
    p.addParameter('PadRatio', 2, @(x) isnumeric(x) && isscalar(x) && x > 0);
    p.addParameter('BaselineWindow', [], @(x) isempty(x) || (isnumeric(x) && numel(x) == 2));
    nv = local_struct2nv(args);
    p.parse(nv{:});
    R = p.Results;
    R.InputField = char(string(R.InputField));

    if isfield(meta, 'validate_only') && meta.validate_only
        return;
    end
    if exist('newtimef', 'file') ~= 2
        error('analysis:tf_compute_source:MissingEEGLAB', ...
            'newtimef not found. Add EEGLAB to the MATLAB path.');
    end
    if ~isfield(state, 'source') || ~isfield(state.source, R.InputField)
        error('analysis:tf_compute_source:MissingSourceEpochs', ...
            'state.source.%s is required.', R.InputField);
    end

    src = state.source.(R.InputField);
    labels = local_condition_labels(state, src, R);
    conds = unique(labels, 'stable');
    timeSec = src.time{1};
    tlimits = [timeSec(1) timeSec(end)] * 1000;
    baseline = NaN;
    if ~isempty(R.BaselineWindow)
        baseline = R.BaselineWindow * 1000;
    end

    out = struct();
    out.label = src.label;
    out.level = src.level;
    out.conditions = struct();
    if isfield(src, 'parcellation'), out.parcellation = src.parcellation; end

    for c = 1:numel(conds)
        idx = find(labels == conds(c));
        X = cat(3, src.trial{idx});
        [nChan, nTime, ~] = size(X);
        [~, ~, ~, tfTimes, tfFreqs] = newtimef( ...
            X(1, :, :), nTime, tlimits, src.fsample, R.Cycles, ...
            'freqs', R.Freqs, 'timesout', R.TimesOut, 'padratio', R.PadRatio, ...
            'baseline', baseline, 'plotersp', 'off', 'plotitc', 'off', 'verbose', 'off');
        power = zeros(nChan, numel(tfFreqs), numel(tfTimes));
        for ch = 1:nChan
            ersp = newtimef( ...
                X(ch, :, :), nTime, tlimits, src.fsample, R.Cycles, ...
                'freqs', R.Freqs, 'timesout', R.TimesOut, 'padratio', R.PadRatio, ...
                'baseline', baseline, 'plotersp', 'off', 'plotitc', 'off', 'verbose', 'off');
            power(ch, :, :) = ersp;
        end
        name = matlab.lang.makeValidName(char(conds(c)));
        out.conditions.(name).power = power;
        out.conditions.(name).times = tfTimes / 1000;
        out.conditions.(name).freqs = tfFreqs;
        out.conditions.(name).n_trial = numel(idx);
        out.conditions.(name).label = char(conds(c));
    end

    state.tf_source.power = out;
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

function labels = local_condition_labels(state, src, R)
    nTr = numel(src.trial);
    if ~isempty(R.ConditionLabels)
        labels = string(R.ConditionLabels(:));
        if numel(labels) ~= nTr
            error('analysis:tf_compute_source:BadConditionLabels', ...
                'ConditionLabels length must match source epochs.');
        end
        return;
    end

    field = char(string(R.ConditionField));
    if ~isempty(field)
        labels = strings(nTr, 1);
        for t = 1:nTr
            v = state.EEG.epoch(t).(field);
            if iscell(v), v = v{1}; end
            labels(t) = string(v);
        end
        return;
    end
    labels = repmat("all", nTr, 1);
end
