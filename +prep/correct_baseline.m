function [EEG, out] = correct_baseline(EEG, varargin)
% CORRECT_BASELINE Performs baseline correction on EEG data.
%   This function applies baseline correction to EEG data, either epoched
%   or continuous, by subtracting the mean of a specified baseline window.
%   It uses the EEGLAB function `pop_rmbase`.
%
% Syntax:
%   [EEG, out] = prep.correct_baseline(EEG, 'param', value, ...)
%
% Input Arguments:
%   EEG         - EEGLAB EEG structure.
%
% Optional Parameters (Name-Value Pairs):
%   'BaselineWindow' - (numeric array, default: [])
%                      A two-element array [start_ms, end_ms] specifying the
%                      baseline window in milliseconds. For example, [-200 0]
%                      for 200ms before stimulus onset. If empty, baseline
%                      correction is skipped.
%   'LogFile'        - (char | string, default: '')
%                      Path to a log file for verbose output. If empty, output
%                      is directed to the command window.
%
% Output Arguments:
%   EEG         - Modified EEGLAB EEG structure with baseline corrected data.
%   out         - Structure containing output information:
%                 out.baseline_window_ms - (numeric array) The baseline window
%                                          used for correction.
%
% Examples:
%   % Example 1: Apply baseline correction from -200ms to 0ms (without pipeline)
%   % Load an EEG dataset first, e.g., EEG = pop_loadset('eeg_data.set');
%   EEG_corrected = prep.correct_baseline(EEG, 'BaselineWindow', [-200 0]);
%   disp('Baseline correction applied from -200ms to 0ms.');
%
%   % Example 2: Usage within a pipeline
%   % Assuming 'pipe' is an initialized pipeline object
%   pipe = pipe.addStep(@prep.correct_baseline, ...
%       'BaselineWindow', [-500 0], ...
%       'LogFile', p.LogFile); %% p.LogFile from pipeline parameters
%   % Then run the pipeline: [EEG_processed, results] = pipe.run(EEG);
%   disp('Baseline correction applied via pipeline.');
%
% See also: pop_rmbase

    % ----------------- Parse inputs -----------------
    p = inputParser;
    p.addRequired('EEG', @isstruct);
    p.addParameter('BaselineWindow', [], @(x) isnumeric(x) && numel(x) == 2);
    p.addParameter('LogFile', '', @(s) ischar(s) || isstring(s));

    p.parse(EEG, varargin{:});
    R = p.Results;

    out = struct();
    out.baseline_window_ms = R.BaselineWindow;

    if isempty(R.BaselineWindow)
        logPrint(R.LogFile, '[correct_baseline] BaselineWindow is empty, skipping baseline correction.');
        return;
    end

    logPrint(R.LogFile, '[correct_baseline] Starting baseline correction.');
    logPrint(R.LogFile, sprintf('[correct_baseline] Baseline window: [%d %d] ms', R.BaselineWindow(1), R.BaselineWindow(2)));

    if EEG.trials > 1
        logPrint(R.LogFile, '[correct_baseline] Applying baseline correction to epoched data.');
    else
        logPrint(R.LogFile, '[correct_baseline] Applying baseline correction to continuous data.');
    end
    % Perform baseline correction
    EEG = pop_rmbase(EEG, R.BaselineWindow);
    EEG = eeg_checkset(EEG); % Always checkset after modifying EEG
    logPrint(R.LogFile, '[correct_baseline] Baseline correction complete.');
end
