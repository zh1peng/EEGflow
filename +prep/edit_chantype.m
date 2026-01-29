function state = edit_chantype(state, args, meta)
%EDIT_CHANTYPE Assign channel types in state.EEG (EEG/EOG/ECG/OTHER).
%
% Purpose & behavior
%   Sets chanlocs(i).type based on label lists. All channels are initialized
%   as 'EEG', then EOG/ECG/OTHER labels override. Useful before bad-channel
%   detection or ICA component classification.
%
% Flow/state contract
%   Required input state fields:
%     - state.EEG (with chanlocs)
%   Updated/created state fields:
%     - state.EEG (chanlocs.type updated)
%     - state.history
%
% Inputs
%   state (struct)
%     - Flow state; see Flow/state contract above.
%   args (struct)
%     - Parameters for this operation (listed below). Merged with state.cfg.edit_chantype if present.
%   meta (struct, optional)
%     - Pipeline meta; supports validate_only/logger.
%
% Parameters
%   - EOGLabel
%       Type: cellstr; Default: {}
%       Labels to mark as 'EOG'.
%   - ECGLabel
%       Type: cellstr; Default: {}
%       Labels to mark as 'ECG'.
%   - OtherLabel
%       Type: cellstr; Default: {}
%       Labels to mark as 'OTHER'.
%   - LogFile
%       Type: char|string; Default: ''
%       Optional log file path.
% Outputs
%   state (struct)
%     - Updated flow state (see Flow/state contract above).
%
% Side effects
%   state.EEG updated in-place; history includes counts per type.
%
% Usage
%   state = prep.edit_chantype(state, struct('EOGLabel',{'VEOG','HEOG'},'ECGLabel',{'ECG1'}));
%
% See also: chans2idx, eeg_checkset

    if nargin < 1 || isempty(state), state = struct(); end
    if nargin < 2 || isempty(args), args = struct(); end
    if nargin < 3 || isempty(meta), meta = struct(); end

    op = 'edit_chantype';
    cfg = state_get_config(state, op);
    params = state_merge(cfg, args);

    p = inputParser;
    p.addRequired('EEG', @isstruct);
    p.addParameter('EOGLabel', {}, @iscellstr);
    p.addParameter('ECGLabel', {}, @iscellstr);
    p.addParameter('OtherLabel', {}, @iscellstr);
    p.addParameter('LogFile', '', @(s) ischar(s) || isstring(s));
    nv = state_struct2nv(params);

    state_require_eeg(state, op);
    p.parse(state.EEG, nv{:});
    R = p.Results;

    if isfield(meta, 'validate_only') && meta.validate_only
        state = state_update_history(state, op, state_strip_eeg_param(R), 'validated', struct());
        return;
    end

    out = struct('types_set', struct('EEG', 0, 'EOG', 0, 'ECG', 0, 'OTHER', 0));
    logPrint(R.LogFile, '[edit_chantype] Starting channel type editing.');

    for i = 1:state.EEG.nbchan
        state.EEG.chanlocs(i).type = 'EEG';
    end

    [eog_idx, eog_not_found] = chans2idx(state.EEG, R.EOGLabel, 'MustExist', false);
    for i = 1:length(eog_idx)
        state.EEG.chanlocs(eog_idx(i)).type = 'EOG';
    end
    if ~isempty(eog_idx)
        logPrint(R.LogFile, sprintf('[edit_chantype] Set %d channels to EOG: %s', length(eog_idx), strjoin(R.EOGLabel, ', ')));
    end
    if ~isempty(eog_not_found)
        logPrint(R.LogFile, sprintf('[edit_chantype] Warning: EOG labels not found: %s', strjoin(eog_not_found, ', ')));
    end

    [ecg_idx, ecg_not_found] = chans2idx(state.EEG, R.ECGLabel, 'MustExist', false);
    for i = 1:length(ecg_idx)
        state.EEG.chanlocs(ecg_idx(i)).type = 'ECG';
    end
    if ~isempty(ecg_idx)
        logPrint(R.LogFile, sprintf('[edit_chantype] Set %d channels to ECG: %s', length(ecg_idx), strjoin(R.ECGLabel, ', ')));
    end
    if ~isempty(ecg_not_found)
        logPrint(R.LogFile, sprintf('[edit_chantype] Warning: ECG labels not found: %s', strjoin(ecg_not_found, ', ')));
    end

    [other_idx, other_not_found] = chans2idx(state.EEG, R.OtherLabel, 'MustExist', false);
    for i = 1:length(other_idx)
        state.EEG.chanlocs(other_idx(i)).type = 'OTHER';
    end
    if ~isempty(other_idx)
        logPrint(R.LogFile, sprintf('[edit_chantype] Set %d channels to OTHER: %s', length(other_idx), strjoin(R.OtherLabel, ', ')));
    end
    if ~isempty(other_not_found)
        logPrint(R.LogFile, sprintf('[edit_chantype] Warning: OTHER labels not found: %s', strjoin(other_not_found, ', ')));
    end

    all_non_eeg_idx = unique([eog_idx(:); ecg_idx(:); other_idx(:)]);
    eeg_idx = setdiff(1:state.EEG.nbchan, all_non_eeg_idx);

    out.types_set.EOG = length(eog_idx);
    out.types_set.ECG = length(ecg_idx);
    out.types_set.OTHER = length(other_idx);
    out.types_set.EEG = length(eeg_idx);

    logPrint(R.LogFile, sprintf('[edit_chantype] Total channels classified: EEG=%d, EOG=%d, ECG=%d, OTHER=%d', ...
        out.types_set.EEG, out.types_set.EOG, out.types_set.ECG, out.types_set.OTHER));
    logPrint(R.LogFile, '[edit_chantype] Channel type editing complete.');

    state.EEG = eeg_checkset(state.EEG);
    state = state_update_history(state, op, state_strip_eeg_param(R), 'success', out);
end
