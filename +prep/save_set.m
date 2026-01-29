function [EEG, out] = save_set(EEG, varargin)
% SAVE_SET  Save EEGLAB dataset (.set)
%
% Usage:
%   [EEG, out] = eegdojo.prep.save_set(EEG, 'filename','x.set','filepath','./out')
%
    p = inputParser;
    % EEG is already the first input argument, no need to add it to inputParser
    p.addParameter('filename','',@ischar); % Changed from addRequired
    p.addParameter('filepath','',@ischar); % Changed from addRequired
    p.addParameter('LogFile', '', @ischar);
    p.parse(varargin{:});
    R = p.Results;

    logPrint(R.LogFile, sprintf('[save_set] Saving dataset: %s/%s', R.filepath, R.filename)); % Added logPrint and prefix
    pop_saveset(EEG, 'filename', R.filename, 'filepath', R.filepath);
    out = struct('savedFile', fullfile(R.filepath, R.filename));
    logPrint(R.LogFile, sprintf('[save_set] Dataset saved: %s/%s', R.filepath, R.filename)); % Added prefix
end