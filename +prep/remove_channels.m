function state = remove_channels(state, args, meta)
%REMOVE_CHANNELS Remove specified channels from state.EEG.
%
% Purpose & behavior
%   Removes channels by index and/or label using pop_select('nochannel', ...).
%   If both index and labels are provided, their union is removed.
%
% Flow/state contract
%   Required input state fields:
%     - state.EEG
%   Updated/created state fields:
%     - state.EEG (channels removed)
%     - state.history
%
% Inputs
%   state (struct)
%     - Flow state; see Flow/state contract above.
%   args (struct)
%     - Parameters for this operation (listed below). Merged with state.cfg.remove_channels if present.
%   meta (struct, optional)
%     - Pipeline meta; supports validate_only/logger.
%
% Parameters
%   - ChanIdx
%       Type: numeric; Shape: vector; Default: []
%       Channel indices to remove.
%   - Chan2remove
%       Type: cellstr|char|string; Default: {}
%       Channel labels to remove; resolved via chans2idx.
%   - LogFile
%       Type: char|string; Default: ''
%       Optional log file path.
% Example args
%   args = struct('Chan2remove', {'ECG'});
%
% Outputs
%   state (struct)
%     - Updated flow state (see Flow/state contract above).
%
% Side effects
%   state.EEG updated in-place; history includes removed indices.
%
% Usage
%   state = prep.remove_channels(state, struct('ChanIdx',[1 5 10]));
%   state = prep.remove_channels(state, struct('Chan2remove',{'EOG1','EOG2'}));
%
% See also: pop_select, chans2idx, prep.select_channels

    if nargin < 1 || isempty(state), state = struct(); end
    if nargin < 2 || isempty(args), args = struct(); end
    if nargin < 3 || isempty(meta), meta = struct(); end

    op = 'remove_channels';
    cfg = state_get_config(state, op);
    params = state_merge(cfg, args);

    p = inputParser;
    p.addRequired('EEG', @isstruct);
    p.addParameter('ChanIdx', [], @(x) isnumeric(x) && isvector(x));
    p.addParameter('Chan2remove', {}, @(x) iscellstr(x) || ischar(x) || isstring(x));
    p.addParameter('LogFile', '', @(s) ischar(s) || isstring(s));
    nv = state_struct2nv(params);

    state_require_eeg(state, op);
    p.parse(state.EEG, nv{:});
    R = p.Results;

    if isfield(meta, 'validate_only') && meta.validate_only
        state = state_update_history(state, op, state_strip_eeg_param(R), 'validated', struct());
        return;
    end

    if isempty(R.ChanIdx) && isempty(R.Chan2remove)
        logPrint(R.LogFile, '[remove_channels] No channels specified for removal. Skipping.');
        state = state_update_history(state, op, state_strip_eeg_param(R), 'skipped', struct());
        return;
    end

    channels_to_remove_idx = [];
    if ~isempty(R.ChanIdx)
        channels_to_remove_idx = [channels_to_remove_idx, R.ChanIdx];
        logPrint(R.LogFile, sprintf('[remove_channels] Channels to remove by index: %s', num2str(R.ChanIdx)));
    end
    if ~isempty(R.Chan2remove)
        if ischar(R.Chan2remove) || isstring(R.Chan2remove)
            R.Chan2remove = cellstr(R.Chan2remove);
        end
        idx_from_labels = chans2idx(state.EEG, R.Chan2remove, 'MustExist', false);
        if ~isempty(idx_from_labels)
            channels_to_remove_idx = [channels_to_remove_idx, idx_from_labels];
            logPrint(R.LogFile, sprintf('[remove_channels] Channels to remove by label: %s (indices: %s)', strjoin(R.Chan2remove, ', '), num2str(idx_from_labels)));
        else
            logPrint(R.LogFile, sprintf('[remove_channels] No channels found for labels: %s', strjoin(R.Chan2remove, ', ')));
        end
    end

    channels_to_remove_idx = unique(channels_to_remove_idx);
    channels_to_remove_idx(channels_to_remove_idx > state.EEG.nbchan | channels_to_remove_idx < 1) = [];

    if isempty(channels_to_remove_idx)
        logPrint(R.LogFile, '[remove_channels] No valid channels to remove after processing inputs. Skipping.');
        state = state_update_history(state, op, state_strip_eeg_param(R), 'skipped', struct());
        return;
    end

    logPrint(R.LogFile, sprintf('[remove_channels] Removing %d channels: %s', length(channels_to_remove_idx), num2str(channels_to_remove_idx)));
    state.EEG = pop_select(state.EEG, 'nochannel', channels_to_remove_idx);
    state.EEG = eeg_checkset(state.EEG);
    logPrint(R.LogFile, '[remove_channels] Channel removal complete.');

    out = struct('removed_idx', channels_to_remove_idx);
    state = state_update_history(state, op, state_strip_eeg_param(R), 'success', out);
end
