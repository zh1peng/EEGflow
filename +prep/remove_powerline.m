function state = remove_powerline(state, args, meta)
%REMOVE_POWERLINE Remove line-noise harmonics from state.EEG.
%
% Purpose & behavior
%   Two methods:
%     - 'cleanline': adaptive sinusoid removal using pop_cleanline.
%     - 'notch': fixed FIR band-stop filters around harmonics using pop_eegfiltnew.
%   Harmonics are generated from Freq up to Nyquist, limited by NHarm.
%
% Flow/state contract
%   Required input state fields:
%     - state.EEG
%   Updated/created state fields:
%     - state.EEG (cleaned)
%     - state.history
%
% Inputs
%   state (struct)
%     - Flow state; see Flow/state contract above.
%   args (struct)
%     - Parameters for this operation (listed below). Merged with state.cfg.remove_powerline if present.
%   meta (struct, optional)
%     - Pipeline meta; supports validate_only/logger.
%
% Parameters
%   - Method
%       Type: char|string; Default: 'cleanline'; Options: cleanline, notch
%       Choose adaptive or fixed notch filtering.
%   - Freq
%       Type: numeric; Shape: scalar; Range: > 0; Default: 50
%       Fundamental line frequency (50 or 60).
%   - BW
%       Type: numeric; Shape: scalar; Range: > 0; Default: 2
%       Half-bandwidth in Hz for notch method.
%   - NHarm
%       Type: numeric; Shape: scalar; Default: 3
%       Number of harmonics to target (below Nyquist).
%   - LogFile
%       Type: char; Default: ''
%       Optional log file path.
% Outputs
%   state (struct)
%     - Updated flow state (see Flow/state contract above).
%
% Side effects
%   state.EEG updated; history includes method and settings.
%
% Usage
%   state = prep.remove_powerline(state, struct('Method','cleanline','Freq',50,'NHarm',4));
%   state = prep.remove_powerline(state, struct('Method','notch','Freq',60,'BW',1,'NHarm',3));
%
% See also: pop_cleanline, pop_eegfiltnew, eeg_checkset

    if nargin < 1 || isempty(state), state = struct(); end
    if nargin < 2 || isempty(args), args = struct(); end
    if nargin < 3 || isempty(meta), meta = struct(); end

    op = 'remove_powerline';
    cfg = state_get_config(state, op);
    params = state_merge(cfg, args);

    p = inputParser;
    p.addRequired('EEG', @isstruct);
    p.addParameter('Method','cleanline', @(s) any(strcmpi(s,{'cleanline','notch'})));
    p.addParameter('Freq', 50, @(x) isnumeric(x) && isscalar(x) && x>0);
    p.addParameter('BW',   2,  @(x) isnumeric(x) && isscalar(x) && x>0);
    p.addParameter('NHarm',3,  @(x) isnumeric(x) && isscalar(x) && x>=1);
    p.addParameter('LogFile', '', @ischar);
    nv = state_struct2nv(params);

    state_require_eeg(state, op);
    p.parse(state.EEG, nv{:});
    R = p.Results;

    if isfield(meta, 'validate_only') && meta.validate_only
        state = state_update_history(state, op, state_strip_eeg_param(R), 'validated', struct());
        return;
    end

    log_step(state, meta, R.LogFile, sprintf('[remove_powerline] --- Removing powerline noise using %s method ---', R.Method));

    fs = state.EEG.srate;
    nyq = fs/2;
    harm = (1:R.NHarm) * R.Freq;
    harm = harm(harm < nyq);
    if isempty(harm)
        error('[remove_powerline] No harmonics found below Nyquist frequency (%.2f Hz). Check Freq and NHarm parameters.', nyq);
    end

    switch lower(R.Method)
        case 'cleanline'
            log_step(state, meta, R.LogFile, sprintf('[remove_powerline] Applying CleanLine at Hz: %s', num2str(harm)));
            state.EEG = pop_cleanline(state.EEG, 'linefreqs', harm, 'newversion', 1);
            state.EEG = eeg_checkset(state.EEG);
            log_step(state, meta, R.LogFile, '[remove_powerline] CleanLine complete.');
        case 'notch'
            log_step(state, meta, R.LogFile, sprintf('[remove_powerline] Applying FIR notch (+/-%.2f Hz) at Hz: %s', R.BW, num2str(harm)));
            for f0 = harm
                lo = max(f0 - R.BW, 0);
                hi = min(f0 + R.BW, nyq);
                if lo <= 0 || hi <= 0 || lo >= hi
                    log_step(state, meta, R.LogFile, sprintf('[remove_powerline] Skipping malformed band [%.2f, %.2f] Hz for harmonic %.2f Hz.', lo, hi, f0));
                    continue;
                end
                state.EEG = pop_eegfiltnew(state.EEG, lo, hi, [], 1, [], 0);
                state.EEG = eeg_checkset(state.EEG);
                log_step(state, meta, R.LogFile, sprintf('[remove_powerline] Applied notch filter for %.2f Hz.', f0));
            end
            log_step(state, meta, R.LogFile, '[remove_powerline] FIR notch complete.');
    end
    log_step(state, meta, R.LogFile, '[remove_powerline] --- Powerline noise removal complete ---');

    out = struct('Method', lower(R.Method), 'Freq', R.Freq, 'NHarm', R.NHarm, 'BW', R.BW);
    state = state_update_history(state, op, state_strip_eeg_param(R), 'success', out);
end
