function state = segment_task(state, args, meta)
%SEGMENT_TASK Segment continuous EEG into epochs around task markers.
%
% Purpose & behavior
%   Uses pop_epoch to extract epochs around specified event types. After
%   epoching, counts epochs per marker and stores counts in output metrics.
%
% Flow/state contract
%   Required input state fields:
%     - state.EEG (continuous with events)
%   Updated/created state fields:
%     - state.EEG (epoched)
%     - state.history
%
% Inputs
%   state (struct)
%     - Flow state; see Flow/state contract above.
%   args (struct)
%     - Parameters for this operation (listed below). Merged with state.cfg.segment_task if present.
%   meta (struct, optional)
%     - Pipeline meta; supports validate_only/logger.
%
% Parameters
%   - Markers
%       Type: cellstr; Default: {}
%       Event types to epoch around.
%   - TimeWindow
%       Type: numeric; Shape: length 2; Default: []
%       Epoch window in milliseconds relative to the marker.
%   - LogFile
%       Type: char|string; Default: ''
%       Optional log file path.
% Outputs
%   state (struct)
%     - Updated flow state (see Flow/state contract above).
%
% Side effects
%   state.EEG updated; history includes epochs_created/total_epochs.
%
% Usage
%   state = prep.segment_task(state, struct('Markers',{'stim_on','resp'},'TimeWindow',[-200 800]));
%
% See also: pop_epoch, eeg_checkset

    if nargin < 1 || isempty(state), state = struct(); end
    if nargin < 2 || isempty(args), args = struct(); end
    if nargin < 3 || isempty(meta), meta = struct(); end

    op = 'segment_task';
    cfg = state_get_config(state, op);
    params = state_merge(cfg, args);

    p = inputParser;
    p.addRequired('EEG', @isstruct);
    p.addParameter('Markers', {}, @iscellstr);
    p.addParameter('TimeWindow', [], @(x) isnumeric(x) && numel(x) == 2);
    p.addParameter('LogFile', '', @(s) ischar(s) || isstring(s));
    nv = state_struct2nv(params);

    state_require_eeg(state, op);
    p.parse(state.EEG, nv{:});
    R = p.Results;

    if isfield(meta, 'validate_only') && meta.validate_only
        state = state_update_history(state, op, state_strip_eeg_param(R), 'validated', struct());
        return;
    end

    out = struct();
    out.epochs_created = struct();

    if isempty(R.Markers) || isempty(R.TimeWindow)
        log_step(state, meta, R.LogFile, '[segment_task] Markers or TimeWindow is empty, skipping task segmentation.');
        state = state_update_history(state, op, state_strip_eeg_param(R), 'skipped', struct());
        return;
    end

    timeWindow_sec = R.TimeWindow / 1000;
    log_step(state, meta, R.LogFile, '[segment_task] ------ Segmenting task data ------');
    log_step(state, meta, R.LogFile, sprintf('[segment_task] Markers: %s, Time window: [%.2f %.2f]s', strjoin(R.Markers, ', '), timeWindow_sec(1), timeWindow_sec(2)));

    log_step(state, meta, R.LogFile, '[segment_task] Calling pop_epoch to segment data...');
    state.EEG = pop_epoch(state.EEG, R.Markers, timeWindow_sec, 'epochinfo', 'yes');

    if isempty(state.EEG.data)
        log_step(state, meta, R.LogFile, '[segment_task error] EEG.data is empty. TimeWindow is in ms. Please check your inputs.');
    end

    state.EEG = eeg_checkset(state.EEG);

    unique_markers = unique(R.Markers);
    epoch_eventtypes = cell(1, state.EEG.trials);
    for e = 1:state.EEG.trials
        et = state.EEG.epoch(e).eventtype;
        if ~iscell(et), et = {et}; end
        et = cellfun(@(x) char(string(x)), et, 'UniformOutput', false);
        epoch_eventtypes{e} = et;
    end

    for i = 1:numel(unique_markers)
        marker = unique_markers{i};
        n_epochs = sum(cellfun(@(et) any(strcmp(marker, et)), epoch_eventtypes));
        safe_marker = matlab.lang.makeValidName(marker, 'ReplacementStyle', 'underscore', 'Prefix', 'm_');
        out.epochs_created.(safe_marker) = n_epochs;
        log_step(state, meta, R.LogFile, sprintf('[segment_task] Created %d epochs for marker %s', n_epochs, marker));
    end

    log_step(state, meta, R.LogFile, sprintf('[segment_task] Total epochs created: %d', state.EEG.trials));
    out.total_epochs = state.EEG.trials;
    log_step(state, meta, R.LogFile, '[segment_task] ------ Task segmentation complete ------');

    state = state_update_history(state, op, state_strip_eeg_param(R), 'success', out);
end
