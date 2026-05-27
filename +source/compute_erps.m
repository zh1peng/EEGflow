function state = compute_erps(state, args, meta)
%COMPUTE_ERPS Average source/parcel epochs by condition.
%
% Input:
%   state.source.epochs.trial{t} = [nSourceOrParcel x nTime]
%
% Output:
%   state.source.erp.conditions.(condition).avg = [nSourceOrParcel x nTime]
%
% This mirrors sensor-level ERP logic, with parcels/source points treated as
% virtual electrodes.

    if nargin < 1 || isempty(state), state = struct(); end
    if nargin < 2 || isempty(args), args = struct(); end
    if nargin < 3 || isempty(meta), meta = struct(); end

    op = 'source_compute_erps';
    cfg0 = state_get_config(state, op);
    params = state_merge(cfg0, args);

    p = inputParser;
    p.addParameter('LogFile', '', @(s) ischar(s) || isstring(s));
    p.addParameter('ConditionLabels', [], @(x) isempty(x) || iscellstr(x) || isstring(x) || isnumeric(x) || iscategorical(x));
    p.addParameter('ConditionField', '', @(s) ischar(s) || isstring(s));
    p.addParameter('BaselineWindow', [], @(x) isempty(x) || (isnumeric(x) && numel(x) == 2 && x(2) > x(1)));
    p.addParameter('KeepTrials', false, @(x) islogical(x) && isscalar(x));

    nv = state_struct2nv(params);
    p.parse(nv{:});
    R = p.Results;

    if isfield(meta, 'validate_only') && meta.validate_only
        state = state_update_history(state, op, R, 'validated', struct());
        return;
    end

    if ~isfield(state, 'source') || ~isfield(state.source, 'epochs')
        error('source:compute_erps:MissingEpochs', 'Run source.reconstruct_epochs before source.compute_erps.');
    end

    src = state.source.epochs;
    labels = local_condition_labels(state, src, R);
    time = src.time{1};
    baseMask = [];
    if ~isempty(R.BaselineWindow)
        baseMask = time >= R.BaselineWindow(1) & time <= R.BaselineWindow(2);
        if ~any(baseMask)
            error('source:compute_erps:BadBaselineWindow', 'BaselineWindow does not overlap source epoch time.');
        end
    end

    conds = unique(labels, 'stable');
    erp = struct();
    erp.label = src.label;
    erp.time = time;
    erp.fsample = src.fsample;
    erp.level = src.level;
    erp.source_pos = src.source_pos;
    erp.unit = src.unit;
    erp.conditions = struct();
    if isfield(src, 'parcellation'), erp.parcellation = src.parcellation; end

    for i = 1:numel(conds)
        c = conds(i);
        idx = find(labels == c);
        Xsum = zeros(size(src.trial{idx(1)}));
        keep = cell(1, numel(idx));
        for k = 1:numel(idx)
            X = double(src.trial{idx(k)});
            if ~isempty(baseMask)
                X = X - mean(X(:, baseMask), 2, 'omitnan');
            end
            Xsum = Xsum + X;
            if R.KeepTrials
                keep{k} = X;
            end
        end
        name = matlab.lang.makeValidName(char(c));
        erp.conditions.(name) = struct();
        erp.conditions.(name).avg = Xsum / numel(idx);
        erp.conditions.(name).n_trial = numel(idx);
        erp.conditions.(name).label = char(c);
        if R.KeepTrials
            erp.conditions.(name).trial = keep;
        end
    end

    if ~isfield(state, 'source') || ~isstruct(state.source), state.source = struct(); end
    state.source.erp = erp;

    out = struct('n_conditions', numel(conds), 'conditions', cellstr(conds(:)));
    log_step(state, meta, R.LogFile, sprintf('[source.compute_erps] Computed %d source ERP condition(s).', numel(conds)));
    state = state_update_history(state, op, R, 'success', out);
end

function labels = local_condition_labels(state, src, R)
    nTr = numel(src.trial);
    if ~isempty(R.ConditionLabels)
        labels = string(R.ConditionLabels(:));
        if numel(labels) ~= nTr
            error('source:compute_erps:BadConditionLabels', 'ConditionLabels length must match number of source epochs.');
        end
        return;
    end

    field = char(string(R.ConditionField));
    if ~isempty(field)
        if ~isfield(state, 'EEG') || ~isfield(state.EEG, 'epoch') || numel(state.EEG.epoch) < nTr
            error('source:compute_erps:MissingEpochField', 'state.EEG.epoch is unavailable for ConditionField=%s.', field);
        end
        labels = strings(nTr, 1);
        for t = 1:nTr
            if isfield(state.EEG.epoch(t), field)
                v = state.EEG.epoch(t).(field);
                if iscell(v), v = v{1}; end
                labels(t) = string(v);
            else
                labels(t) = "missing";
            end
        end
        return;
    end

    labels = repmat("all", nTr, 1);
end
