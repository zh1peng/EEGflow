function state = interpolate(state, args, meta)
%INTERPOLATE Interpolate missing channels using original channel locations.
%
% Purpose & behavior
%   Restores channels that were removed by interpolating from EEG.urchanlocs
%   using spherical interpolation (pop_interp). Requires EEG.urchanlocs.
%
% Flow/state contract
%   Required input state fields:
%     - state.EEG
%     - state.EEG.urchanlocs (original channel locations)
%   Updated/created state fields:
%     - state.EEG (interpolated)
%     - state.history
%
% Inputs
%   state (struct)
%     - Flow state; see Flow/state contract above.
%   args (struct)
%     - Parameters for this operation (listed below). Merged with state.cfg.interpolate if present.
%   meta (struct, optional)
%     - Pipeline meta; supports validate_only/logger.
%
% Parameters
%   - LogFile
%       Type: char; Default: ''
%       Optional log file path.
% Outputs
%   state (struct)
%     - Updated flow state (see Flow/state contract above).
%
% Side effects
%   state.EEG updated in-place; history includes interpolated channel labels.
%
% Usage
%   state = prep.interpolate(state);
%
% See also: pop_interp, eeg_checkset, prep.remove_bad_channels

    if nargin < 1 || isempty(state), state = struct(); end
    if nargin < 2 || isempty(args), args = struct(); end
    if nargin < 3 || isempty(meta), meta = struct(); end

    op = 'interpolate';
    cfg = state_get_config(state, op);
    params = state_merge(cfg, args);

    p = inputParser;
    p.addRequired('EEG', @isstruct);
    p.addParameter('LogFile', '', @ischar);
    nv = state_struct2nv(params);

    state_require_eeg(state, op);
    p.parse(state.EEG, nv{:});
    R = p.Results;

    if isfield(meta, 'validate_only') && meta.validate_only
        state = state_update_history(state, op, state_strip_eeg_param(R), 'validated', struct());
        return;
    end

    log_step(state, meta, R.LogFile, '[interpolate] Starting channel interpolation.');

    if ~isfield(state.EEG, 'urchanlocs') || isempty(state.EEG.urchanlocs)
        error('[interpolate] No original channel locations (EEG.urchanlocs) found.');
    end

    original_chans = {state.EEG.urchanlocs.labels};
    current_chans = {state.EEG.chanlocs.labels};
    chans_to_interp = setdiff(original_chans, current_chans);

    if isempty(chans_to_interp)
        log_step(state, meta, R.LogFile, '[interpolate] Skipping interpolation: No channels to interpolate found.');
        state = state_update_history(state, op, state_strip_eeg_param(R), 'skipped', struct());
        return;
    end

    log_step(state, meta, R.LogFile, sprintf('[interpolate] Interpolating %d channels: %s', numel(chans_to_interp), strjoin(chans_to_interp, ', ')));
    state.EEG = pop_interp(state.EEG, state.EEG.urchanlocs, 'spherical');
    state.EEG = eeg_checkset(state.EEG);
    log_step(state, meta, R.LogFile, '[interpolate] Interpolation complete.');

    out = struct('interpolated_channels', chans_to_interp);
    state = state_update_history(state, op, state_strip_eeg_param(R), 'success', out);
end
