function state = downsample(state, args, meta)
%DOWNSAMPLE Downsample state.EEG to a target sampling rate.
%
% Purpose & behavior
%   Uses EEGLAB pop_resample to change the sampling rate. The actual
%   resulting rate is taken from EEG.srate after resampling.
%
% Flow/state contract
%   Required input state fields:
%     - state.EEG
%   Updated/created state fields:
%     - state.EEG (resampled)
%     - state.history
%
% Inputs
%   state (struct)
%     - Flow state; see Flow/state contract above.
%   args (struct)
%     - Parameters for this operation (listed below). Merged with state.cfg.downsample if present.
%   meta (struct, optional)
%     - Pipeline meta; supports validate_only/logger.
%
% Parameters
%   - Rate
%       Type: numeric; Default: 250
%       Target sampling rate in Hz.
%   - LogFile
%       Type: char; Default: ''
%       Optional log file path.
% Example args
%   args = struct('Rate', 250);
%
% Outputs
%   state (struct)
%     - Updated flow state (see Flow/state contract above).
%
% Side effects
%   state.EEG updated in-place; history includes new_sampling_rate.
%
% Usage
%   state = prep.downsample(state, struct('Rate', 128));
%
% See also: pop_resample, eeg_checkset

    if nargin < 1 || isempty(state), state = struct(); end
    if nargin < 2 || isempty(args), args = struct(); end
    if nargin < 3 || isempty(meta), meta = struct(); end

    op = 'downsample';
    cfg = state_get_config(state, op);
    params = state_merge(cfg, args);

    p = inputParser;
    p.addRequired('EEG', @isstruct);
    p.addParameter('Rate', 250, @isnumeric);
    p.addParameter('LogFile', '', @ischar);
    nv = state_struct2nv(params);

    state_require_eeg(state, op);
    p.parse(state.EEG, nv{:});
    R = p.Results;

    if isfield(meta, 'validate_only') && meta.validate_only
        state = state_update_history(state, op, state_strip_eeg_param(R), 'validated', struct());
        return;
    end

    log_step(state, meta, R.LogFile, sprintf('[downsample] Downsampling data to %d Hz.', R.Rate));
    state.EEG = pop_resample(state.EEG, R.Rate);
    state.EEG = eeg_checkset(state.EEG);
    log_step(state, meta, R.LogFile, sprintf('[downsample] Downsampling complete. New sampling rate: %d Hz.', state.EEG.srate));

    out = struct('new_sampling_rate', state.EEG.srate);
    state = state_update_history(state, op, state_strip_eeg_param(R), 'success', out);
end
