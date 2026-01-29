function [EEG, out] = edit_chantype(EEG, varargin)
% EDIT_CHANTYPE Sets the type for each channel ('EEG', 'EOG', 'ECG', 'OTHER').
%   This function classifies channels based on provided labels. Any channel not
%   specified as EOG, ECG, or OTHER is defaulted to EEG. This is useful for
%   constraining subsequent analyses (e.g., bad channel detection) to specific
%   channel types, and for identifying artifactual components during ICA.
%
% Syntax:
%   [EEG, out] = prep.edit_chantype(EEG, 'param', value, ...)
%
% Input Arguments:
%   EEG         - EEGLAB EEG structure.
%
% Optional Parameters (Name-Value Pairs):
%   'EOGLabel'   - (cell array of strings, default: {})
%                     Labels of channels to be classified as Electrooculogram (EOG).
%   'ECGLabel'   - (cell array of strings, default: {})
%                     Labels of channels to be classified as Electrocardiogram (ECG).
%   'OtherLabel' - (cell array of strings, default: {})
%                     Labels of channels to be classified as 'OTHER'.
%   'LogFile'     - (char | string, default: '')
%                     Path to the log file for recording processing information.
%                     If empty, output is directed to the command window.
%
% Output Arguments:
%   EEG         - Modified EEGLAB EEG structure with updated channel types.
%   out         - Structure containing output information:
%                 out.types_set  - (struct) A summary of how many channels
%                                  were set to each type (EEG, EOG, ECG, OTHER).
%
% Examples:
%   % Example 1: Classify EOG, ECG, and other channels (without pipeline)
%   % Load an EEG dataset first, e.g., EEG = pop_loadset('eeg_data.set');
%   EEG_typed = prep.edit_chantype(EEG, ...
%       'EOGLabel', {'VEOG', 'HEOG'}, ...
%       'ECGLabel', {'ECG1'}, ...
%       'OtherLabel', {'TRIG'});
%   disp('Channel types updated.');
%
%   % Example 2: Usage within a pipeline
%   % Assuming 'pipe' is an initialized pipeline object
%   pipe = pipe.addStep(@prep.edit_chantype, ...
%       'EOGLabel', {'VEOG', 'HEOG'}, ...
%       'ECGLabel', {'ECG1'}, ...
%       'OtherLabel', {'TRIG'}, ...
%       'LogFile', p.LogFile); %% p.LogFile from pipeline parameters
%   % Then run the pipeline: [EEG_processed, results] = pipe.run(EEG);
%   disp('Channel types updated via pipeline.');
%
% See also: chans2idx, eeg_checkset

    % ----------------- Parse inputs -----------------
    p = inputParser;
    p.addRequired('EEG', @isstruct);
    p.addParameter('EOGLabel', {}, @iscellstr);
    p.addParameter('ECGLabel', {}, @iscellstr);
    p.addParameter('OtherLabel', {}, @iscellstr);
    p.addParameter('LogFile', '', @(s) ischar(s) || isstring(s));

    p.parse(EEG, varargin{:});
    R = p.Results;

    out = struct('types_set', struct('EEG', 0, 'EOG', 0, 'ECG', 0, 'OTHER', 0));


    logPrint(R.LogFile, '[edit_chantype] Starting channel type editing.');

    % Default all channels to 'EEG' first
    for i = 1:EEG.nbchan
        EEG.chanlocs(i).type = 'EEG';
    end

    % Set EOG channel types
    [eog_idx, eog_not_found] = chans2idx(EEG, R.EOGLabel, 'MustExist', false); % Added 'MustExist', false
    for i = 1:length(eog_idx)
        EEG.chanlocs(eog_idx(i)).type = 'EOG';
    end
    if ~isempty(eog_idx)
        logPrint(R.LogFile, sprintf('[edit_chantype] Set %d channels to EOG: %s', length(eog_idx), strjoin(R.EOGLabel, ', ')));
    end
    if ~isempty(eog_not_found)
        logPrint(R.LogFile, sprintf('[edit_chantype] Warning: EOG labels not found: %s', strjoin(eog_not_found, ', ')));
    end

    % Set ECG channel types
    [ecg_idx, ecg_not_found] = chans2idx(EEG, R.ECGLabel, 'MustExist', false); % Added 'MustExist', false
    for i = 1:length(ecg_idx)
        EEG.chanlocs(ecg_idx(i)).type = 'ECG';
    end
    if ~isempty(ecg_idx)
        logPrint(R.LogFile, sprintf('[edit_chantype] Set %d channels to ECG: %s', length(ecg_idx), strjoin(R.ECGLabel, ', ')));
    end
    if ~isempty(ecg_not_found)
        logPrint(R.LogFile, sprintf('[edit_chantype] Warning: ECG labels not found: %s', strjoin(ecg_not_found, ', ')));
    end

    % Set OTHER channel types
    [other_idx, other_not_found] = chans2idx(EEG, R.OtherLabel, 'MustExist', false); % Added 'MustExist', false
    for i = 1:length(other_idx)
        EEG.chanlocs(other_idx(i)).type = 'OTHER';
    end
    if ~isempty(other_idx)
        logPrint(R.LogFile, sprintf('[edit_chantype] Set %d channels to OTHER: %s', length(other_idx), strjoin(R.OtherLabel, ', ')));
    end
    if ~isempty(other_not_found)
        logPrint(R.LogFile, sprintf('[edit_chantype] Warning: OTHER labels not found: %s', strjoin(other_not_found, ', ')));
    end

    % Recalculate EEG channels (those not set to something else)
    all_non_eeg_idx = unique([eog_idx(:); ecg_idx(:); other_idx(:)]); % Ensure unique indices
    eeg_idx = setdiff(1:EEG.nbchan, all_non_eeg_idx);

    % Summarize and log the final counts
    out.types_set.EOG = length(eog_idx);
    out.types_set.ECG = length(ecg_idx);
    out.types_set.OTHER = length(other_idx);
    out.types_set.EEG = length(eeg_idx);

    logPrint(R.LogFile, sprintf('[edit_chantype] Total channels classified: EEG=%d, EOG=%d, ECG=%d, OTHER=%d', ...
        out.types_set.EEG, out.types_set.EOG, out.types_set.ECG, out.types_set.OTHER));
    logPrint(R.LogFile, '[edit_chantype] Channel type editing complete.');

    EEG = eeg_checkset(EEG);


end
