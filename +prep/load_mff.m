function [EEG, out] = load_mff(~, varargin)
% LOAD_MFF  Load an EGI .mff dataset
%
% Usage:
%   [EEG, out] = eegdojo.prep.load_mff([], 'filename','subject1.mff','filepath','./data')
%
% Description:
%   Loads an EGI .mff file using EEGLAB's pop_mffimport function.
%   The function logs progress if a LogFile is specified.
%
% Inputs (Name-Value pairs):
%   'filename' - Name of the .mff file (string)
%   'filepath' - Path to the folder containing the file (string)
%   'LogFile'  - Path to a log file (optional)
%
% Outputs:
%   EEG - EEGLAB EEG structure
%   out - Struct with metadata (loadedFile)

    p = inputParser; 
    p.addParameter('filename','',@ischar);
    p.addParameter('filepath','',@ischar);
    p.addParameter('LogFile', '', @ischar);
    p.parse(varargin{:});

    R = p.Results;
    fullPath = fullfile(R.filepath, R.filename);

    logPrint(R.LogFile, sprintf('[load_mff] Loading MFF dataset: %s', fullPath));

    % --- Load MFF file ---
    EEG = pop_mffimport({fullPath}, {'code'}, 0, 0);

    % --- Post-processing ---
    EEG = eeg_checkset(EEG);
    out = struct('loadedFile', fullPath);

    logPrint(R.LogFile, sprintf('[load_mff] Dataset loaded successfully: %s', fullPath));

end
