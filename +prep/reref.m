function [EEG, out] = reref(EEG, varargin)
% REREF  Re-references EEG data to the average reference.
%   This function re-references the EEG data to the average of all channels.
%   Optionally, specific channels can be excluded from the average calculation
%   (e.g., EOG channels or known bad channels).
%
% Syntax:
%   [EEG, out] = prep.reref(EEG, 'param', value, ...)
%
% Input Arguments:
%   EEG         - EEGLAB EEG structure.
%
% Optional Parameters (Name-Value Pairs):
%   'excludeLabels' - (cell array of strings | string, default: {})
%                     A cell array of channel labels (e.g., {'EOG1', 'EOG2'})
%                     or a single string label to exclude from the average
%                     reference calculation. These channels will still be
%                     present in the output EEG structure but will not
%                     contribute to the average.
%   'LogFile'       - (char | string, default: '')
%                     Path to a log file for verbose output. If empty, output
%                     is directed to the command window.
%
% Output Arguments:
%   EEG         - Modified EEGLAB EEG structure with data re-referenced.
%   out         - Structure containing details of the re-referencing:
%                 out.excluded_labels: Cell array of channel labels that were
%                                      excluded from the average reference.
%
% Examples:
%   % Example 1: Re-reference to average, excluding EOG channels (without pipeline)
%   % Load an EEG dataset first, e.g., EEG = pop_loadset('eeg_data.set');
%   [EEG_reref, reref_info] = prep.reref(EEG, ...
%       'excludeLabels', {'VEOG', 'HEOG'}, ...
%       'LogFile', 'reref_log.txt');
%   disp('EEG data re-referenced to average, excluding EOG channels.');
%   disp(['Excluded channels: ', strjoin(reref_info.excluded_labels, ', ')]);
%
%   % Example 2: Re-reference to average (with pipeline)
%   % Assuming 'pipe' is an initialized pipeline object
%   pipe = pipe.addStep(@prep.reref, ...
%       'LogFile', p.LogFile); %% p.LogFile from pipeline parameters
%   % Then run the pipeline: [EEG_processed, results] = pipe.run(EEG);
%   disp('EEG data re-referenced to average.');
%
% See also: pop_reref

    p = inputParser;
    p.addRequired('EEG', @isstruct);
    p.addParameter('ExcludeLabel', {}, @(x) iscell(x) || ischar(x));
    p.addParameter('LogFile', '', @ischar);

    p.parse(EEG, varargin{:});
    R = p.Results;

    out = struct(); % Initialize out struct
    out.excluded_labels = R.ExcludeLabel;


    if ischar(R.ExcludeLabel)
        excludeLabels = {R.ExcludeLabel};
    else
        excludeLabels = R.ExcludeLabel;
    end

    log_msg = '[reref] Re-referencing data to average';
    if ~isempty(excludeLabels)
        log_msg = [log_msg, sprintf(', excluding channels: %s', strjoin(excludeLabels, ', '))];
    end
    logPrint(R.LogFile, [log_msg, '.']);

    if isempty(excludeLabels)
        logPrint(R.LogFile, '[reref] Applying average reference to all channels.');
        EEG = pop_reref(EEG, []);
    else
        labels = {EEG.chanlocs.labels};
        excludeIdx = find(ismember(labels, excludeLabels));
        logPrint(R.LogFile, sprintf('[reref] Applying average reference, excluding %d channels.', length(excludeIdx)));
        EEG = pop_reref(EEG, [], 'exclude', excludeIdx);
    end

    EEG = eeg_checkset(EEG);

    logPrint(R.LogFile, '[reref] Re-referencing complete.');

end