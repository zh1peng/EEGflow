function [EEG, out] = downsample(EEG, varargin)
% DOWNSAMPLE Downsamples EEG data to a specified frequency.
%
% This function reduces the sampling rate of the EEG data using EEGLAB's
% `pop_resample` function. This can be useful for reducing file size and
% processing time, especially for data acquired at very high sampling rates.
%
% Inputs:
%   EEG         - EEGLAB EEG structure.
%   varargin    - Optional parameters:
%     'freq'    - (numeric) The target sampling frequency in Hz. Default is 250.
%     'LogFile' - (char) Path to the log file for recording processing
%                 information. Default is ''.
%
% Outputs:
%   EEG         - Modified EEGLAB EEG structure with downsampled data.
%   out         - Structure containing output information:
%     .new_sampling_rate - (numeric) The actual new sampling rate of the EEG data.
%
% Examples:
%   % 1. Downsample EEG data to 128 Hz:
%   EEG = downsample(EEG, 'freq', 128);
%
%   % 2. Usage within a pipeline:
%   %    (Assuming 'p' is a parameter structure containing 'p.LogFile')
%   pipe = pipe.addStep(@prep.downsample, ...
%       'freq', 250, ...
%       'LogFile', p.LogFile);
%
% See also: pop_resample

    % ----------------- Parse inputs -----------------
    p = inputParser;
    p.addRequired('EEG', @isstruct);
    p.addParameter('Rate', 250, @isnumeric);
    p.addParameter('LogFile', '', @ischar);

    p.parse(EEG, varargin{:});
    R = p.Results;

    out = struct(); % Initialize output structure
    out.new_sampling_rate = R.Rate;

    logPrint(R.LogFile, sprintf('[downsample] Downsampling data to %d Hz.', R.Rate));
    EEG = pop_resample(EEG, R.Rate);
    EEG = eeg_checkset(EEG); % Update EEG structure after changes
    logPrint(R.LogFile, sprintf('[downsample] Downsampling complete. New sampling rate: %d Hz.', EEG.srate));
    out.new_sampling_rate = EEG.srate; % Ensure output reflects actual srate

end
