function [EEG, out] = filter(EEG, varargin)
% FILTER Applies high-pass and low-pass filters to EEG data.
%
% This function applies FIR (Finite Impulse Response) filters to the EEG data
% using EEGLAB's `pop_eegfiltnew` function. It supports both high-pass and
% low-pass filtering.
%
% Syntax:
%   [EEG, out] = prep.filter(EEG, 'param', value, ...)
%
% Input Arguments:
%   EEG         - EEGLAB EEG structure.
%
% Optional Parameters (Name-Value Pairs):
%   'LowCutoff' - (numeric, default: -1)
%                 High-pass cutoff frequency in Hz. If -1 or 0, no high-pass
%                 filter is applied.
%   'HighCutoff'- (numeric, default: -1)
%                 Low-pass cutoff frequency in Hz. If -1 or 0, no low-pass
%                 filter is applied.
%   'LogFile'   - (char | string, default: '')
%                 Path to a log file for verbose output. If empty, output
%                 is directed to the command window.
%
% Output Arguments:
%   EEG         - Modified EEGLAB EEG structure with filtered data.
%   out         - Structure containing output information:
%                 out.LowCutoff   - (numeric) The high-pass frequency used.
%                 out.HighCutoff  - (numeric) The low-pass frequency used.
%
% Examples:
%   % Example 1: Apply a band-pass filter from 0.5 Hz to 30 Hz (without pipeline)
%   % Load an EEG dataset first, e.g., EEG = pop_loadset('eeg_data.set');
%   EEG_filtered = prep.filter(EEG, 'LowCutoff', 0.5, 'HighCutoff', 30);
%   disp('EEG data band-pass filtered from 0.5 to 30 Hz.');
%
%   % Example 2: Apply only a high-pass filter at 1 Hz (with pipeline)
%   % Assuming 'pipe' is an initialized pipeline object
%   pipe = pipe.addStep(@prep.filter, ...
%       'LowCutoff', 1, ...
%       'LogFile', p.LogFile); %% p.LogFile from pipeline parameters
%   % Then run the pipeline: [EEG_processed, results] = pipe.run(EEG);
%   disp('EEG data high-pass filtered via pipeline.');
%
% See also: pop_eegfiltnew

    % ----------------- Parse inputs -----------------
    p = inputParser;
    p.addRequired('EEG', @isstruct);
    p.addParameter('LowCutoff', -1, @isnumeric); % Changed from HPfreq
    p.addParameter('HighCutoff', -1, @isnumeric); % Changed from LPfreq
    p.addParameter('LogFile', '', @ischar);

    p.parse(EEG, varargin{:});
    R = p.Results;

    out = struct(); % Initialize output structure
    out.LowCutoff = R.LowCutoff; % Changed from HPfreq
    out.HighCutoff = R.HighCutoff; % Changed from LPfreq

    logPrint(R.LogFile, '[filter] Starting filtering process.');
    
    % Construct log message for filter parameters
    filter_msg = '';
    if R.LowCutoff > 0, filter_msg = [filter_msg, sprintf('High-pass: %.2f Hz. ', R.LowCutoff)]; end % Changed from HPfreq
    if R.HighCutoff > 0, filter_msg = [filter_msg, sprintf('Low-pass: %.2f Hz.', R.HighCutoff)]; end % Changed from LPfreq
    if isempty(filter_msg), filter_msg = 'No filter applied (LowCutoff and HighCutoff are <= 0).'; end % Changed parameter names
    logPrint(R.LogFile, sprintf('[filter] %s', filter_msg));

    % Input validation for frequencies
    if R.LowCutoff > 0 && R.HighCutoff > 0 && R.LowCutoff >= R.HighCutoff
        error('[filter] High-pass frequency (%.2f Hz) must be lower than low-pass frequency (%.2f Hz).', R.LowCutoff, R.HighCutoff); % Changed parameter names
    end
    if R.LowCutoff < 0 && R.HighCutoff < 0
        logPrint(R.LogFile, '[filter] No valid filter frequencies provided. Skipping filtering.');
        return; % Skip filtering if no valid frequencies
    end


    % Apply high-pass filter if specified
    if R.LowCutoff > 0 % Changed from HPfreq
        EEG = pop_eegfiltnew(EEG, 'locutoff', R.LowCutoff, 'plotfreqz', 0);
        EEG = eeg_checkset(EEG);
    end
    
    % Apply low-pass filter if specified
    if R.HighCutoff > 0 % Changed from LPfreq
        EEG = pop_eegfiltnew(EEG, 'hicutoff', R.HighCutoff,  'plotfreqz', 0);
        EEG = eeg_checkset(EEG);
    end
    
    logPrint(R.LogFile, '[filter] Filtering complete.');

end