function state = select_channels(state, args, meta)
%SELECT_CHANNELS Keep only specified channels in state.EEG.
%
% Purpose & behavior
%   Selects channels by index and/or label and drops all others using
%   pop_select('channel', ...). If both index and labels are provided, the
%   union is kept.
%
% Flow/state contract
%   Required input state fields:
%     - state.EEG
%   Updated/created state fields:
%     - state.EEG (channel subset)
%     - state.history
%
% Inputs
%   state (struct)
%     - Flow state; see Flow/state contract above.
%   args (struct)
%     - Parameters for this operation (listed below). Merged with state.cfg.select_channels if present.
%   meta (struct, optional)
%     - Pipeline meta; supports validate_only/logger.
%
% Parameters
%   - ChanIdx
%       Type: numeric; Shape: vector; Default: []
%       Channel indices to keep.
%   - ChanLabels
%       Type: cellstr|char; Default: {}
%       Channel labels to keep; resolved via chans2idx.
%   - LogFile
%       Type: char|string; Default: ''
%       Optional log file path.
% Outputs
%   state (struct)
%     - Updated flow state (see Flow/state contract above).
%
% Side effects
%   state.EEG updated in-place; history includes indices kept.
%
% Usage
%   state = prep.select_channels(state, struct('ChanIdx',[1 5 10]));
%   state = prep.select_channels(state, struct('ChanLabels',{'Cz','Fz'}));
%
% See also: pop_select, chans2idx, prep.remove_channels

    if nargin < 1 || isempty(state), state = struct(); end
    if nargin < 2 || isempty(args), args = struct(); end
    if nargin < 3 || isempty(meta), meta = struct(); end

    op = 'select_channels';
    cfg = state_get_config(state, op);
    params = state_merge(cfg, args);

    p = inputParser;
    p.addRequired('EEG', @isstruct);
    p.addParameter('ChanIdx', [], @(x) isnumeric(x) && isvector(x));
    p.addParameter('ChanLabels', {}, @(x) iscellstr(x) || ischar(x));
    p.addParameter('LogFile', '', @(s) ischar(s) || isstring(s));
    nv = state_struct2nv(params);

    state_require_eeg(state, op);
    p.parse(state.EEG, nv{:});
    R = p.Results;

    if isfield(meta, 'validate_only') && meta.validate_only
        state = state_update_history(state, op, state_strip_eeg_param(R), 'validated', struct());
        return;
    end

    if isempty(R.ChanIdx) && isempty(R.ChanLabels)
        log_step(state, meta, R.LogFile, '[select_channels] No channels specified for selection. Returning original EEG.');
        state = state_update_history(state, op, state_strip_eeg_param(R), 'skipped', struct());
        return;
    end

    channels_to_select_idx = [];

    if ~isempty(R.ChanIdx)
        channels_to_select_idx = [channels_to_select_idx, R.ChanIdx];
        log_step(state, meta, R.LogFile, sprintf('[select_channels] Channels to select by index: %s', num2str(R.ChanIdx)));
    end

    if ~isempty(R.ChanLabels)
        if ischar(R.ChanLabels)
            R.ChanLabels = {R.ChanLabels};
        end
        idx_from_labels = chans2idx(state.EEG, R.ChanLabels, 'MustExist', false);
        if ~isempty(idx_from_labels)
            channels_to_select_idx = [channels_to_select_idx, idx_from_labels];
            log_step(state, meta, R.LogFile, sprintf('[select_channels] Channels to select by label: %s (indices: %s)', strjoin(R.ChanLabels, ', '), num2str(idx_from_labels)));
        else
            log_step(state, meta, R.LogFile, sprintf('[select_channels] No channels found for labels: %s', strjoin(R.ChanLabels, ', ')));
        end
    end

    channels_to_select_idx = unique(channels_to_select_idx); % Ensure unique indices
    channels_to_select_idx(channels_to_select_idx > state.EEG.nbchan | channels_to_select_idx < 1) = []; % Remove out-of-bounds indices

    if isempty(channels_to_select_idx)
        log_step(state, meta, R.LogFile, '[select_channels] No valid channels to select after processing inputs. Returning original EEG.');
        state = state_update_history(state, op, state_strip_eeg_param(R), 'skipped', struct());
        return;
    end

    log_step(state, meta, R.LogFile, sprintf('[select_channels] Selecting %d channels: %s', length(channels_to_select_idx), num2str(channels_to_select_idx)));
    state.EEG = pop_select(state.EEG, 'channel', channels_to_select_idx);
    state.EEG = eeg_checkset(state.EEG);
    log_step(state, meta, R.LogFile, '[select_channels] Channel selection complete.');

    out = struct('ChanIdx', channels_to_select_idx);
    state = state_update_history(state, op, state_strip_eeg_param(R), 'success', out);

end
