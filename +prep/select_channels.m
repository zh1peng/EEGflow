function EEG = select_channels(EEG, varargin)
% SELECT_CHANNELS  Selects specified channels from an EEGLAB dataset.
%   This function provides a flexible way to select channels from an EEG
%   dataset, either by their numerical indices or by their labels. It's
%   useful for focusing on specific channels for analysis.
%
% Syntax:
%   EEG = prep.select_channels(EEG, 'param', value, ...)
%
% Input Arguments:
%   EEG         - EEGLAB EEG structure.
%
% Optional Parameters (Name-Value Pairs):
%   'ChanIdx'       - (numeric array, default: [])
%                     Numerical indices of channels to select.
%   'ChanLabels'    - (cell array of strings, default: {})
%                     Labels of channels to select (e.g., {'Cz', 'Fz'}).
%                     If both 'ChanIdx' and 'ChanLabels' are provided,
%                     channels specified by either will be selected.
%   'LogFile'       - (char | string, default: '')
%                     Path to a log file for verbose output. If empty, output
%                     is directed to the command window.
%
% Output Arguments:
%   EEG         - Modified EEGLAB EEG structure with only specified channels.
%
% Examples:
%   % Example 1: Select channels by index (without pipeline)
%   % Load an EEG dataset first, e.g., EEG = pop_loadset('eeg_data.set');
%   EEG_selected = prep.select_channels(EEG, ...
%       'ChanIdx', [1 5 10], ...
%       'LogFile', 'channel_selection_log.txt');
%   disp('Channels 1, 5, and 10 selected.');
%
%   % Example 2: Select channels by label (with pipeline)
%   % Assuming 'pipe' is an initialized pipeline object
%   pipe = pipe.addStep(@prep.select_channels, ...
%       'ChanLabels', {'Fp1', 'Fp2', 'Fz'}, ...
%       'LogFile', p.LogFile); % p.LogFile from pipeline parameters
%   % Then run the pipeline: [EEG_processed, results] = pipe.run(EEG);
%   disp('Specific frontal channels selected via pipeline.');
%
% See also: pop_select, chans2idx

    % ----------------- Parse inputs -----------------
    p = inputParser;
    p.addRequired('EEG', @isstruct);
    p.addParameter('ChanIdx', [], @(x) isnumeric(x) && isvector(x));
    p.addParameter('ChanLabels', {}, @(x) iscellstr(x) || ischar(x));
    p.addParameter('LogFile', '', @(s) ischar(s) || isstring(s));

    p.parse(EEG, varargin{:});
    R = p.Results;

    if isempty(R.ChanIdx) && isempty(R.ChanLabels)
        logPrint(R.LogFile, '[select_channels] No channels specified for selection. Returning original EEG.');
        return;
    end

    channels_to_select_idx = [];

    if ~isempty(R.ChanIdx)
        channels_to_select_idx = [channels_to_select_idx, R.ChanIdx];
        logPrint(R.LogFile, sprintf('[select_channels] Channels to select by index: %s', num2str(R.ChanIdx)));
    end

    if ~isempty(R.ChanLabels)
        if ischar(R.ChanLabels)
            R.ChanLabels = {R.ChanLabels};
        end
        idx_from_labels = chans2idx(EEG, R.ChanLabels, 'MustExist', false); 
        if ~isempty(idx_from_labels)
            channels_to_select_idx = [channels_to_select_idx, idx_from_labels];
            logPrint(R.LogFile, sprintf('[select_channels] Channels to select by label: %s (indices: %s)', strjoin(R.ChanLabels, ', '), num2str(idx_from_labels)));
        else
            logPrint(R.LogFile, sprintf('[select_channels] No channels found for labels: %s', strjoin(R.ChanLabels, ', ')));
        end
    end

    channels_to_select_idx = unique(channels_to_select_idx); % Ensure unique indices
    channels_to_select_idx(channels_to_select_idx > EEG.nbchan | channels_to_select_idx < 1) = []; % Remove out-of-bounds indices

    if isempty(channels_to_select_idx)
        logPrint(R.LogFile, '[select_channels] No valid channels to select after processing inputs. Returning original EEG.');
        return;
    end

    logPrint(R.LogFile, sprintf('[select_channels] Selecting %d channels: %s', length(channels_to_select_idx), num2str(channels_to_select_idx)));
    EEG = pop_select(EEG, 'channel', channels_to_select_idx);
    EEG = eeg_checkset(EEG);
    logPrint(R.LogFile, '[select_channels] Channel selection complete.');

end