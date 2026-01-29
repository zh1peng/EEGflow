function [EEG, out] = segment_task(EEG, varargin)
% SEGMENT_TASK  Segments continuous EEG data into epochs around specified event markers.
%   This function is designed for task-related EEG data where epochs are
%   created relative to specific time-locked event markers (e.g., stimulus
%   onset, response, trial start). It extracts segments of data within a
%   defined time window around these markers, preparing the data for
%   event-related potential (ERP) or other epoch-based analyses.
%
% Syntax:
%   [EEG, out] = prep.segment_task(EEG, 'param', value, ...)
%
% Input Arguments:
%   EEG         - EEGLAB EEG structure (continuous data with events).
%
% Optional Parameters (Name-Value Pairs):
%   'Markers'       - (cell array of strings, default: {})
%                     A cell array of event marker strings (e.g., {'S1', 'S2', 'Response'})
%                     around which to create epochs.
%   'TimeWindow'    - (numeric array [start_time end_time], default: [])
%                     A two-element numeric array specifying the time window
%                     for epoch extraction, relative to the event marker, in milliseconds.
%                     E.g., [-500 1500] means from 500 ms before to 1500 ms after the marker.
%   'LogFile'       - (char | string, default: '')
%                     Path to a log file for verbose output. If empty, output
%                     is directed to the command window.
%
% Output Arguments:
%   EEG         - Modified EEGLAB EEG structure with data segmented into epochs.
%   out         - Structure containing details of the segmentation:
%                 out.epochs_created: A structure where field names are marker
%                                     types and values are the number of epochs
%                                     created for that marker.
%                 out.total_epochs: The total number of epochs created across
%                                   all specified markers.
%
% Examples:
%   % Example 1: Segment EEG around 'stim_on' and 'resp' markers (without pipeline)
%   % Load a continuous EEG dataset with events, e.g., EEG = pop_loadset('task_eeg.set');
%   [EEG_epoched, seg_info] = prep.segment_task(EEG, ...
%       'Markers', {'stim_on', 'resp'}, ...
%       'TimeWindow', [-200 800], ...
%       'LogFile', 'task_segmentation_log.txt');
%   disp('Task data segmented.');
%   disp('Epochs created per marker:');
%   disp(seg_info.epochs_created);
%   disp(['Total epochs: ', num2str(seg_info.total_epochs)]);
%
%   % Example 2: Segment with a different time window (with pipeline)
%   % Assuming 'pipe' is an initialized pipeline object
%   pipe = pipe.addStep(@prep.segment_task, ...
%       'Markers', {'trial_start'}, ...
%       'TimeWindow', [-1000 2000], ...
%       'LogFile', p.LogFile); %% p.LogFile from pipeline parameters
%   % Then run the pipeline: [EEG_processed, results] = pipe.run(EEG);
%   disp('Task data segmented via pipeline.');
%
% See also: pop_epoch

    % ----------------- Parse inputs -----------------
    p = inputParser;
    p.addRequired('EEG', @isstruct);
    p.addParameter('Markers', {}, @iscellstr);
    p.addParameter('TimeWindow', [], @(x) isnumeric(x) && numel(x) == 2);
    p.addParameter('LogFile', '', @(s) ischar(s) || isstring(s));

    p.parse(EEG, varargin{:});
    R = p.Results;

    out = struct();
    out.epochs_created = struct();

    if isempty(R.Markers) || isempty(R.TimeWindow)
        logPrint(R.LogFile, '[segment_task] Markers or TimeWindow is empty, skipping task segmentation.');
        return;
    end

    timeWindow_sec = R.TimeWindow / 1000;

    logPrint(R.LogFile, '[segment_task] ------ Segmenting task data ------');
    logPrint(R.LogFile, sprintf('[segment_task] Markers: %s, Time window: [%.2f %.2f]s', strjoin(R.Markers, ', '), timeWindow_sec(1), timeWindow_sec(2)));

    % Segment the data into epochs
    logPrint(R.LogFile, '[segment_task] Calling pop_epoch to segment data...');
    EEG = pop_epoch(EEG, R.Markers, timeWindow_sec, 'epochinfo', 'yes');
    
    if isempty(EEG.data)
        logPrint(R.LogFile, '[segment_task error] EEG.data is empty.Timewindow is in ms. Please check your inputs');
    end

    EEG = eeg_checkset(EEG);
    % Log the number of epochs for each marker type (robust version)
unique_markers = unique(R.Markers);

% Preprocess epoch event types to handle cell/char/numeric variations
epoch_eventtypes = cell(1, EEG.trials);
for e = 1:EEG.trials
    et = EEG.epoch(e).eventtype;
    if ~iscell(et), et = {et}; end
    % Convert all entries to char strings
    et = cellfun(@(x) char(string(x)), et, 'UniformOutput', false);
    epoch_eventtypes{e} = et;
end

for i = 1:numel(unique_markers)
    marker = unique_markers{i};
    % Count epochs containing this marker
    n_epochs = sum(cellfun(@(et) any(strcmp(marker, et)), epoch_eventtypes));
    % Sanitize field name (avoid '-' or spaces)
    safe_marker = matlab.lang.makeValidName(marker, 'ReplacementStyle', 'underscore', 'Prefix', 'm_');
    out.epochs_created.(safe_marker) = n_epochs;
    logPrint(R.LogFile, sprintf('[segment_task] Created %d epochs for marker %s', n_epochs, marker));
end

logPrint(R.LogFile, sprintf('[segment_task] Total epochs created: %d', EEG.trials));
    out.total_epochs = EEG.trials;

    logPrint(R.LogFile, '[segment_task] ------ Task segmentation complete ------');

end
