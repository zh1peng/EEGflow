function state = filter(state, args, meta)
%FILTER Apply high-pass and/or low-pass FIR filters to state.EEG.
%
% Purpose & behavior
%   Uses EEGLAB pop_eegfiltnew to apply a high-pass (LowCutoff) and/or
%   low-pass (HighCutoff) FIR filter. If both cutoffs are negative, the
%   step is skipped. If both are positive, LowCutoff must be < HighCutoff.
%
% Flow/state contract
%   Required input state fields:
%     - state.EEG
%   Updated/created state fields:
%     - state.EEG (filtered)
%     - state.history
%
% Inputs
%   state (struct)
%     - Flow state; see Flow/state contract above.
%   args (struct)
%     - Parameters for this operation (listed below). Merged with state.cfg.filter if present.
%   meta (struct, optional)
%     - Pipeline meta; supports validate_only/logger.
%
% Parameters
%   - LowCutoff
%       Type: numeric; Default: -1
%       High-pass cutoff in Hz. <=0 disables high-pass.
%   - HighCutoff
%       Type: numeric; Default: -1
%       Low-pass cutoff in Hz. <=0 disables low-pass.
%   - LogFile
%       Type: char; Default: ''
%       Optional log file path.
% Example args
%   args = struct('LowCutoff', 0.5, 'HighCutoff', 30);
%
% Outputs
%   state (struct)
%     - Updated flow state (see Flow/state contract above).
%
% Side effects
%   state.EEG updated in-place.
%
% Usage
%   state = prep.filter(state, struct('LowCutoff',0.5,'HighCutoff',30));
%   state = prep.filter(state, struct('LowCutoff',1)); % high-pass only
%
% See also: pop_eegfiltnew, eeg_checkset, prep.remove_powerline

    if nargin < 1 || isempty(state), state = struct(); end
    if nargin < 2 || isempty(args), args = struct(); end
    if nargin < 3 || isempty(meta), meta = struct(); end

    op = 'filter';
    cfg = state_get_config(state, op);
    params = state_merge(cfg, args);

    p = inputParser;
    p.addRequired('EEG', @isstruct);
    p.addParameter('LowCutoff', -1, @isnumeric);
    p.addParameter('HighCutoff', -1, @isnumeric);
    p.addParameter('LogFile', '', @ischar);
    nv = state_struct2nv(params);

    state_require_eeg(state, op);
    p.parse(state.EEG, nv{:});
    R = p.Results;

    if isfield(meta, 'validate_only') && meta.validate_only
        state = state_update_history(state, op, state_strip_eeg_param(R), 'validated', struct());
        return;
    end

    logPrint(R.LogFile, '[filter] Starting filtering process.');

    if R.LowCutoff > 0 && R.HighCutoff > 0 && R.LowCutoff >= R.HighCutoff
        error('[filter] High-pass frequency (%.2f Hz) must be lower than low-pass frequency (%.2f Hz).', ...
            R.LowCutoff, R.HighCutoff);
    end
    if R.LowCutoff < 0 && R.HighCutoff < 0
        logPrint(R.LogFile, '[filter] No valid filter frequencies provided. Skipping filtering.');
        state = state_update_history(state, op, state_strip_eeg_param(R), 'skipped', struct());
        return;
    end

    if R.LowCutoff > 0
        state.EEG = pop_eegfiltnew(state.EEG, 'locutoff', R.LowCutoff, 'plotfreqz', 0);
        state.EEG = eeg_checkset(state.EEG);
    end
    if R.HighCutoff > 0
        state.EEG = pop_eegfiltnew(state.EEG, 'hicutoff', R.HighCutoff, 'plotfreqz', 0);
        state.EEG = eeg_checkset(state.EEG);
    end

    logPrint(R.LogFile, '[filter] Filtering complete.');
    out = struct('LowCutoff', R.LowCutoff, 'HighCutoff', R.HighCutoff);
    state = state_update_history(state, op, state_strip_eeg_param(R), 'success', out);
end
