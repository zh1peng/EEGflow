function state = correct_baseline(state, args, meta)
%CORRECT_BASELINE Apply baseline correction to state.EEG.
%
% Purpose & behavior
%   Uses EEGLAB pop_rmbase to subtract the mean of a specified baseline
%   window (ms) from each epoch (or continuous data). If BaselineWindow is
%   empty, the step is skipped.
%
% Flow/state contract
%   Required input state fields:
%     - state.EEG
%   Updated/created state fields:
%     - state.EEG (baseline-corrected)
%     - state.history
%
% Inputs
%   state (struct)
%     - Flow state; see Flow/state contract above.
%   args (struct)
%     - Parameters for this operation (listed below). Merged with state.cfg.correct_baseline if present.
%   meta (struct, optional)
%     - Pipeline meta; supports validate_only/logger.
%
% Parameters
%   - BaselineWindow
%       Type: numeric; Shape: length 2; Default: []
%       Baseline window in milliseconds relative to epoch time 0.
%   - LogFile
%       Type: char|string; Default: ''
%       Optional log file path.
% Outputs
%   state (struct)
%     - Updated flow state (see Flow/state contract above).
%
% Side effects
%   state.EEG updated in-place; history includes the applied window.
%
% Usage
%   state = prep.correct_baseline(state, struct('BaselineWindow', [-200 0]));
%
% See also: pop_rmbase, eeg_checkset, prep.segment_task

    if nargin < 1 || isempty(state), state = struct(); end
    if nargin < 2 || isempty(args), args = struct(); end
    if nargin < 3 || isempty(meta), meta = struct(); end

    op = 'correct_baseline';
    cfg = state_get_config(state, op);
    params = state_merge(cfg, args);

    p = inputParser;
    p.addRequired('EEG', @isstruct);
    p.addParameter('BaselineWindow', [], @(x) isnumeric(x) && numel(x) == 2);
    p.addParameter('LogFile', '', @(s) ischar(s) || isstring(s));
    nv = state_struct2nv(params);

    state_require_eeg(state, op);
    p.parse(state.EEG, nv{:});
    R = p.Results;

    if isfield(meta, 'validate_only') && meta.validate_only
        state = state_update_history(state, op, state_strip_eeg_param(R), 'validated', struct());
        return;
    end

    if isempty(R.BaselineWindow)
        logPrint(R.LogFile, '[correct_baseline] BaselineWindow is empty, skipping baseline correction.');
        state = state_update_history(state, op, state_strip_eeg_param(R), 'skipped', struct());
        return;
    end

    logPrint(R.LogFile, '[correct_baseline] Starting baseline correction.');
    logPrint(R.LogFile, sprintf('[correct_baseline] Baseline window: [%d %d] ms', R.BaselineWindow(1), R.BaselineWindow(2)));

    if state.EEG.trials > 1
        logPrint(R.LogFile, '[correct_baseline] Applying baseline correction to epoched data.');
    else
        logPrint(R.LogFile, '[correct_baseline] Applying baseline correction to continuous data.');
    end
    state.EEG = pop_rmbase(state.EEG, R.BaselineWindow);
    state.EEG = eeg_checkset(state.EEG);
    logPrint(R.LogFile, '[correct_baseline] Baseline correction complete.');

    out = struct('baseline_window_ms', R.BaselineWindow);
    state = state_update_history(state, op, state_strip_eeg_param(R), 'success', out);
end
