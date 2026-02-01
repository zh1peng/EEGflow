function state = interpolate_bad_channels_epoch(state, args, meta)
%INTERPOLATE_BAD_CHANNELS_EPOCH Detect and interpolate bad channels per epoch.
%
% Purpose & behavior
%   Uses single_epoch_channel_properties + min_z to flag bad channels for
%   each epoch, then interpolates them with h_epoch_interp_spl. Useful after
%   epoching when channel artifacts are transient.
%
% Flow/state contract
%   Required input state fields:
%     - state.EEG (epoched)
%   Updated/created state fields:
%     - state.EEG (interpolated per epoch)
%     - state.EEG.etc.EEGdojo.BadChanEpochCell
%     - state.history
%
% Inputs
%   state (struct)
%     - Flow state; see Flow/state contract above.
%   args (struct)
%     - Parameters for this operation (listed below). Merged with state.cfg.interpolate_bad_channels_epoch if present.
%   meta (struct, optional)
%     - Pipeline meta; supports validate_only/logger.
%
% Parameters
%   - LogFile
%       Type: char|string; Default: ''
%       Optional log file path.
%   - ExcludeLabel
%       Type: char|string; Default: {}
%       Channels to exclude from detection/interpolation.
% Outputs
%   state (struct)
%     - Updated flow state (see Flow/state contract above).
%
% Side effects
%   state.EEG updated; history includes bad channel lists per epoch.
%
% Usage
%   state = prep.interpolate_bad_channels_epoch(state, struct('ExcludeLabel',{'EOG1','EOG2'}));
%
% See also: single_epoch_channel_properties, h_epoch_interp_spl, chans2idx

    if nargin < 1 || isempty(state), state = struct(); end
    if nargin < 2 || isempty(args), args = struct(); end
    if nargin < 3 || isempty(meta), meta = struct(); end

    op = 'interpolate_bad_channels_epoch';
    cfg = state_get_config(state, op);
    params = state_merge(cfg, args);

    p = inputParser;
    p.addRequired('EEG', @isstruct);
    p.addParameter('LogFile', '', @(s) ischar(s) || isstring(s));
    p.addParameter('ExcludeLabel', {}, @(x) ischar(x) || isstring(x) || iscell(x));
    nv = state_struct2nv(params);

    state_require_eeg(state, op);
    p.parse(state.EEG, nv{:});
    R = p.Results;

    if isfield(meta, 'validate_only') && meta.validate_only
        state = state_update_history(state, op, state_strip_eeg_param(R), 'validated', struct());
        return;
    end

    if ~isempty(R.ExcludeLabel)
        excludeIdx = chans2idx(state.EEG, R.ExcludeLabel);
        IdxDetect  = setdiff(1:state.EEG.nbchan, excludeIdx);
        log_step(state, meta, R.LogFile, sprintf('Epoch-wise bad-channel detection: excluding labels=%s (idx=%s).', ...
            labels2str(R.ExcludeLabel), mat2str(excludeIdx)));
    else
        excludeIdx = [];
        IdxDetect  = 1:state.EEG.nbchan;
        log_step(state, meta, R.LogFile, 'Epoch-wise bad-channel detection: no excluded channels.');
    end

    log_step(state, meta, R.LogFile, 'Identifying bad channels per epoch...');

    bad_chan_cell = cell(1, state.EEG.trials);
    for epoch_i = 1:state.EEG.trials
        bad_chan_epoch_list = single_epoch_channel_properties(state.EEG, epoch_i, IdxDetect);
        tmp_bad_rel = find(min_z(bad_chan_epoch_list) == 1);
        tmp_bad_abs = IdxDetect(tmp_bad_rel);
        bad_chan_cell{epoch_i} = tmp_bad_abs;
        if ~isempty(tmp_bad_abs)
            log_step(state, meta, R.LogFile, sprintf('Epoch %d - Interpolated chans: %d, Details(idx)=%s', ...
                epoch_i, numel(tmp_bad_abs), mat2str(tmp_bad_abs)));
        end
    end

    log_step(state, meta, R.LogFile, 'Interpolating bad channels at the epoch level...');
    state.EEG = h_epoch_interp_spl(state.EEG, bad_chan_cell);
    log_step(state, meta, R.LogFile, 'Bad channels interpolated successfully.');

    out = struct();
    out.bad_chan_cell = bad_chan_cell;
    out.excludeIdx    = excludeIdx;
    out.idxDetect     = IdxDetect;

    if ~isfield(state.EEG, 'etc') || isempty(state.EEG.etc), state.EEG.etc = struct(); end
    if ~isfield(state.EEG.etc, 'EEGdojo') || isempty(state.EEG.etc.EEGdojo)
        state.EEG.etc.EEGdojo = struct();
    end
    state.EEG.etc.EEGdojo.BadChanEpochCell = bad_chan_cell;
    state.EEG.etc.EEGdojo.BadChanEpoch_ExcludeIdx = excludeIdx;

    state = state_update_history(state, op, state_strip_eeg_param(R), 'success', out);
end

function s = labels2str(L)
    if ischar(L) || isstring(L)
        s = char(L);
    else
        s = strjoin(cellfun(@char, L, 'uni', false), ',');
    end
end
