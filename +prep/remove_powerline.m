function EEG = remove_powerline(EEG, varargin)
% REMOVE_POWERLINE  Removes powerline (mains) noise from EEG data.
%   This function offers two methods for powerline noise removal:
%   1. CleanLine: An adaptive method that estimates and removes sinusoidal
%      noise components.
%   2. FIR Notch: Applies fixed-width FIR band-stop filters at the fundamental
%      frequency and its harmonics.
%   The function automatically identifies harmonics up to the Nyquist frequency.
%
% Syntax:
%   EEG = prep.remove_powerline(EEG, 'param', value, ...)
%
% Input Arguments:
%   EEG         - EEGLAB EEG structure.
%
% Optional Parameters (Name-Value Pairs):
%   'Method'    - (char | string, 'cleanline' | 'notch', default: 'cleanline')
%                 Method to use for powerline noise removal.
%                 'cleanline': Uses pop_cleanline for adaptive noise removal.
%                 'notch': Applies FIR notch filters using pop_eegfiltnew.
%   'Freq'      - (numeric, default: 50)
%                 Fundamental powerline frequency in Hz (e.g., 50 for Europe,
%                 60 for North America).
%   'BW'        - (numeric, default: 2)
%                 Half-bandwidth in Hz for the FIR notch filter (±BW around
%                 each target frequency). Only applicable when 'Method' is 'notch'.
%   'NHarm'     - (numeric, default: 3)
%                 Number of harmonics to target. The function will only apply
%                 filters to harmonics that are below the Nyquist frequency.
%   'LogFile'   - (char | string, default: '')
%                 Path to a log file for verbose output. If empty, output
%                 is directed to the command window.
%
% Output Arguments:
%   EEG         - Modified EEGLAB EEG structure with powerline noise removed.
%
% Examples:
%   % Example 1: Remove 50 Hz powerline noise using CleanLine (without pipeline)
%   % Load an EEG dataset first, e.g., EEG = pop_loadset('eeg_data.set');
%   EEG_cleaned = prep.remove_powerline(EEG, ...
%       'Method', 'cleanline', ...
%       'Freq', 50, ...
%       'NHarm', 4, ...
%       'LogFile', 'powerline_log.txt');
%   disp('Powerline noise removal complete using CleanLine.');
%
%   % Example 2: Remove 60 Hz powerline noise using FIR notch filters (with pipeline)
%   % Assuming 'pipe' is an initialized pipeline object
%   pipe = pipe.addStep(@prep.remove_powerline, ...
%       'Method', 'notch', ...
%       'Freq', 60, ...
%       'BW', 1, ...
%       'NHarm', 3, ...
%       'LogFile', p.LogFile); %% p.LogFile from pipeline parameters
%   % Then run the pipeline: [EEG_processed, results] = pipe.run(EEG);
%   disp('Powerline noise removal complete using FIR notch filters.');
%
% See also: pop_cleanline, pop_eegfiltnew

    % ---- Parse inputs ----
    p = inputParser;
    p.addRequired('EEG', @isstruct);
    p.addParameter('Method','cleanline', @(s) any(strcmpi(s,{'cleanline','notch'})));
    p.addParameter('Freq', 50, @(x) isnumeric(x) && isscalar(x) && x>0);
    p.addParameter('BW',   2,  @(x) isnumeric(x) && isscalar(x) && x>0);
    p.addParameter('NHarm',3,  @(x) isnumeric(x) && isscalar(x) && x>=1);
    p.addParameter('LogFile', '', @ischar);
    p.parse(EEG, varargin{:});
    R = p.Results;


    logPrint(R.LogFile, sprintf('[remove_powerline] --- Removing powerline noise using %s method ---', R.Method));

    fs = EEG.srate;
    nyq = fs/2;

    % Build harmonic list under Nyquist
    harm = (1:R.NHarm) * R.Freq;
    harm = harm(harm < nyq);
    if isempty(harm)
        error('[remove_powerline] No harmonics found below Nyquist frequency (%.2f Hz). Check Freq and NHarm parameters.', nyq);
    end

    switch lower(R.Method)
        case 'cleanline'
            % --- Adaptive removal using CleanLine ---
            % pop_cleanline accepts vector of line freqs

            logPrint(R.LogFile,sprintf('[remove_powerline] Applying CleanLine at Hz: %s', num2str(harm)));

            EEG = pop_cleanline(EEG, 'linefreqs', harm, 'newversion', 1);
            EEG = eeg_checkset(EEG);
            logPrint(R.LogFile, '[remove_powerline] CleanLine complete.');


        case 'notch'
            % --- Fixed FIR band-stop around each harmonic: [f-BW, f+BW] ---

            logPrint(R.LogFile,sprintf('[remove_powerline] Applying FIR notch (±%.2f Hz) at Hz: %s', R.BW, num2str(harm)));

            for f0 = harm
                lo = max(f0 - R.BW, 0);   % lower edge
                hi = min(f0 + R.BW, nyq); % upper edge
                if lo <= 0 || hi <= 0 || lo >= hi
                    logPrint(R.LogFile, '[remove_powerline] Skipping malformed band [%.2f, %.2f] Hz for harmonic %.2f Hz.', lo, hi, f0);
                    continue; % skip malformed bands
                end
                % pop_eegfiltnew: band-stop when 'revfilt'=1
                % EEG = pop_eegfiltnew(EEG, locutoff, hicutoff, filtorder, revfilt, usefft, plotfreqz)
                EEG = pop_eegfiltnew(EEG, lo, hi, [], 1, [], 0);
                EEG = eeg_checkset(EEG);
                logPrint(R.LogFile, '[remove_powerline] Applied notch filter for %.2f Hz.', f0);
            end
            logPrint(R.LogFile, '[remove_powerline] FIR notch complete.');
    end
    logPrint(R.LogFile, '[remove_powerline] --- Powerline noise removal complete ---');
end