function state = reref(state, args, meta)
%REREF Re-reference state.EEG to average reference.
%
% Purpose & behavior
%   Uses pop_reref to compute an average reference across channels, with
%   optional exclusion of specific labels (e.g., EOG).
%
% Flow/state contract
%   Required input state fields:
%     - state.EEG
%   Updated/created state fields:
%     - state.EEG (re-referenced)
%     - state.history
%
% Inputs
%   state (struct)
%     - Flow state; see Flow/state contract above.
%   args (struct)
%     - Parameters for this operation (listed below). Merged with state.cfg.reref if present.
%   meta (struct, optional)
%     - Pipeline meta; supports validate_only/logger.
%
% Parameters
%   - ExcludeLabel
%       Type: char|string; Default: {}
%       Labels to exclude from the average reference computation.
%   - LogFile
%       Type: char; Default: ''
%       Optional log file path.
% Example args
%   args = struct('ExcludeLabel', {});
%
% Outputs
%   state (struct)
%     - Updated flow state (see Flow/state contract above).
%
% Side effects
%   state.EEG updated; history includes excluded labels.
%
% Usage
%   state = prep.reref(state, struct('ExcludeLabel',{'VEOG','HEOG'}));
%
% See also: pop_reref, eeg_checkset

    if nargin < 1 || isempty(state), state = struct(); end
    if nargin < 2 || isempty(args), args = struct(); end
    if nargin < 3 || isempty(meta), meta = struct(); end

    op = 'reref';
    cfg = state_get_config(state, op);
    params = state_merge(cfg, args);

    p = inputParser;
    p.addRequired('EEG', @isstruct);
    p.addParameter('ExcludeLabel', {}, @(x) iscell(x) || ischar(x) || isstring(x));
    p.addParameter('LogFile', '', @ischar);
    nv = state_struct2nv(params);

    state_require_eeg(state, op);
    p.parse(state.EEG, nv{:});
    R = p.Results;

    if isfield(meta, 'validate_only') && meta.validate_only
        state = state_update_history(state, op, state_strip_eeg_param(R), 'validated', struct());
        return;
    end

    out = struct();
    out.excluded_labels = R.ExcludeLabel;

    if ischar(R.ExcludeLabel) || isstring(R.ExcludeLabel)
        excludeLabels = cellstr(R.ExcludeLabel);
    else
        excludeLabels = R.ExcludeLabel;
    end

    log_msg = '[reref] Re-referencing data to average';
    if ~isempty(excludeLabels)
        log_msg = [log_msg, sprintf(', excluding channels: %s', strjoin(excludeLabels, ', '))];
    end
    logPrint(R.LogFile, [log_msg, '.']);

    if isempty(excludeLabels)
        logPrint(R.LogFile, '[reref] Applying average reference to all channels.');
        state.EEG = pop_reref(state.EEG, []);
    else
        labels = {state.EEG.chanlocs.labels};
        excludeIdx = find(ismember(labels, excludeLabels));
        logPrint(R.LogFile, sprintf('[reref] Applying average reference, excluding %d channels.', length(excludeIdx)));
        state.EEG = pop_reref(state.EEG, [], 'exclude', excludeIdx);
    end

    state.EEG = eeg_checkset(state.EEG);
    logPrint(R.LogFile, '[reref] Re-referencing complete.');

    state = state_update_history(state, op, state_strip_eeg_param(R), 'success', out);
end
