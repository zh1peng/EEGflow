function EEG = remove_channels(EEG, varargin)
% REMOVE_CHANNELS  Removes specified channels from an EEGLAB dataset.
%   This function provides a flexible way to remove channels from an EEG
%   dataset, either by their numerical indices or by their labels. It's
%   useful for excluding channels that are known to be problematic or
%   irrelevant for a specific analysis.
%
% Syntax:
%   EEG = prep.remove_channels(EEG, 'param', value, ...)
%
% Input Arguments:
%   EEG         - EEGLAB EEG structure.
%
% Optional Parameters (Name-Value Pairs):
%   'ChanIdx'       - (numeric array, default: [])
%                     Numerical indices of channels to remove.
%   'Chan2remove'    - (cell array of strings, default: {})
%                     Labels of channels to remove (e.g., {'Cz', 'Fz'}).
%                     If both 'ChanIdx' and 'Chan2remove' are provided,
%                     channels specified by both will be removed.
%   'LogFile'       - (char | string, default: '')
%                     Path to a log file for verbose output. If empty, output
%                     is directed to the command window.
%
% Output Arguments:
%   EEG         - Modified EEGLAB EEG structure with specified channels removed.
%
% Examples:
%   % Example 1: Remove channels by index (without pipeline)
%   % Load an EEG dataset first, e.g., EEG = pop_loadset('eeg_data.set');
%   EEG_cleaned = prep.remove_channels(EEG, ...
%       'ChanIdx', [1 5 10], ...
%       'LogFile', 'channel_removal_log.txt');
%   disp('Channels 1, 5, and 10 removed.');
%
%   % Example 2: Remove channels by label (with pipeline)
%   % Assuming 'pipe' is an initialized pipeline object
%   pipe = pipe.addStep(@prep.remove_channels, ...
%       'Chan2remove', {'EOG1', 'EOG2', 'ECG'}, ...
%       'LogFile', p.LogFile); % p.LogFile from pipeline parameters
%   % Then run the pipeline: [EEG_processed, results] = pipe.run(EEG);
%   disp('EOG and ECG channels removed via pipeline.');
%
% See also: pop_select, chans2idx

    % ----------------- Parse inputs -----------------
    p = inputParser;
    p.addRequired('EEG', @isstruct);
    p.addParameter('ChanIdx', [], @(x) isnumeric(x) && isvector(x));
    p.addParameter('Chan2remove', {}, @(x) iscellstr(x) || ischar(x));
    p.addParameter('LogFile', '', @(s) ischar(s) || isstring(s));

    p.parse(EEG, varargin{:});
    R = p.Results;

    if isempty(R.ChanIdx) && isempty(R.Chan2remove)
        logPrint(R.LogFile, '[remove_channels] No channels specified for removal. Skipping.');
        return;
    end

    channels_to_remove_idx = [];

    if ~isempty(R.ChanIdx)
        channels_to_remove_idx = [channels_to_remove_idx, R.ChanIdx];
        logPrint(R.LogFile, sprintf('[remove_channels] Channels to remove by index: %s', num2str(R.ChanIdx)));
    end

    if ~isempty(R.Chan2remove)
        if ischar(R.Chan2remove)
            R.Chan2remove = {R.Chan2remove};
        end
        % Changed call to chans2idx to use explicit name-value pair
        idx_from_labels = chans2idx(EEG, R.Chan2remove, 'MustExist', false); 
        if ~isempty(idx_from_labels)
            channels_to_remove_idx = [channels_to_remove_idx, idx_from_labels];
            logPrint(R.LogFile, sprintf('[remove_channels] Channels to remove by label: %s (indices: %s)', strjoin(R.Chan2remove, ', '), num2str(idx_from_labels)));
        else
            logPrint(R.LogFile, sprintf('[remove_channels] No channels found for labels: %s', strjoin(R.Chan2remove, ', ')));
        end
    end

    channels_to_remove_idx = unique(channels_to_remove_idx); % Ensure unique indices
    channels_to_remove_idx(channels_to_remove_idx > EEG.nbchan | channels_to_remove_idx < 1) = []; % Remove out-of-bounds indices

    if isempty(channels_to_remove_idx)
        logPrint(R.LogFile, '[remove_channels] No valid channels to remove after processing inputs. Skipping.');
        return;
    end

    % Debugging: Inspect arguments before pop_select
    param_name = 'nochannel';
    param_value = channels_to_remove_idx;
    logPrint(R.LogFile, sprintf('[remove_channels] Removing %d channels: %s', length(channels_to_remove_idx), num2str(channels_to_remove_idx)));
    EEG = pop_select(EEG, param_name, param_value); % This is the line in question
    EEG = eeg_checkset(EEG);
    logPrint(R.LogFile, '[remove_channels] Channel removal complete.');


end
