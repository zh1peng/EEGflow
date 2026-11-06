function Out = collect_segments(varargin)
% COLLECT_SEGMENTS Build a study-level container from cropped segments of many EEGLAB .set files.
%   This function is designed to find EEGLAB .set files and extract a single,
%   continuous data segment from each file based on specified start and end
%   markers. It's ideal for analyzing data from continuous recordings like
%   movie-watching or resting-state paradigms.
%
%   It includes an option to standardize the length of all extracted segments
%   by resampling them to a specified duration or sample count. This is
%   particularly useful for movie-watching data where segment lengths may
%   vary slightly across subjects.
%
% Output Structure:
%   The output is a single struct `Out` with two main components:
%   1. Out.meta: A struct containing shared information across all subjects.
%      This includes:
%       .fs              - Sampling rate of the processed data.
%       .srate           - (Same as fs) Sampling rate.
%       .chanlocs        - Channel locations structure from the first subject.
%       .start_marker    - The event marker used to define the start of the segment.
%       .end_marker      - The event marker used to define the end of the segment.
%       .padding_sec     - Seconds of padding added before the start and after the end marker.
%       .expected_length - The target number of samples for resampling.
%       .created_at      - Timestamp of when the extraction was run.
%       .run_tag         - A user-defined tag for this specific extraction run.
%
%   2. Out.sub_...: A series of dynamically named fields for each subject
%      (e.g., Out.sub_001, Out.sub_S02). Each subject field is a struct containing:
%       .data            - A [channels x time] matrix of the extracted (and optionally resampled) segment.
%       .crop_info       - A struct with info from `prep.crop_by_markers`.
%       .resample_info   - (If resampling is enabled) A struct with details on the resampling:
%                          .original_length - Number of samples before resampling.
%                          .expected_length - Target number of samples.
%                          .missing_samples - The difference between expected and original length.
%
% Name-Value Pair Arguments:
%   'study_path' (char, REQUIRED)
%       The absolute path to the root directory containing the .set files.
%
%   'StartMarker' (char/string, REQUIRED)
%       The event marker string that defines the beginning of the segment to extract.
%
%   'EndMarker' (char/string, REQUIRED)
%       The event marker string that defines the end of the segment.
%
%   'movie_duration_sec' (numeric, default: [])
%       The expected duration of the movie/segment in seconds. If provided,
%       each segment is resampled to match this duration. Use this OR 'expected_length'.
%
%   'expected_length' (numeric, default: [])
%       The expected number of samples in the final segment. If provided,
%       each segment is resampled to this length. Use this OR 'movie_duration_sec'.
%
%   'check_quality' (logical, default: false)
%       Compute all QC metrics on a temporary 1 Hz high-pass copy BEFORE
%       cropping. These describe the input recording, not only the segment.
%       The analysis data follow locutoff/hicutoff independently.
%
%   'searchstring' (char, default: '.*\.set$')
%       A regular expression to find specific .set files within the study_path.
%
%   'recursive' (logical, default: true)
%       If true, searches for files in subdirectories of study_path.
%
%   'subject_parser' (char, default: '(?<sub>.+)')
%       A regular expression with a named token '(?<sub>...)' to extract a unique
%       subject ID from each filename.
%
%   'subjects_to_include' (numeric vector | 'all', default: 'all')
%       A numeric vector of indices to select a subset of the found subjects.
%       For example, `1:10` will process only the first 10 subjects found
%       (after natural sorting of filenames). If 'all', all subjects are processed.
%
%   'chan_include' (cellstr/string, default: {})
%       A list of channel labels to *include*. All other channels will be removed.
%
%   'chan_exclude' (cellstr/string, default: {})
%       A list of channel labels to *exclude*. All other channels will be kept.
%
%   'PadSec' (numeric, default: 0)
%       Number of seconds to add as padding before the StartMarker and after the EndMarker.
%
%   'to_single' (logical, default: false)
%       If true, casts the output data matrices to the 'single' data type to save memory.
%
%   'save_path' (char, default: '')
%       If provided, the final 'Out' struct is saved to this full path.
%
%   'run_tag' (char, default: timestamp)
%       A custom string tag to identify this extraction run, stored in Out.meta.
%
% Examples:
% 
%   % Example 1: Basic Extraction
%   MovieData = movie.collect_segments( ...
%       'study_path', 'C:\EEG_Data\MovieStudy', ...
%       'StartMarker', 'movie_start',
%       'EndMarker', 'movie_end');
%
%   % Example 2: Resampling to a Fixed Duration
%   % Extracts a movie segment and resamples it to be exactly 300 seconds long.
%   MovieData = movie.collect_segments( ...
%       'study_path', 'C:\EEG_Data\MovieStudy', ...
%       'StartMarker', 'start',
%       'EndMarker', 'end',
%       'movie_duration_sec', 300, ...
%       'run_tag', 'movie_300s_resampled');
%
%   % Example 3: Resampling to a Fixed Sample Length
%   % Extracts a segment and resamples it to exactly 150000 samples.
%   MovieData = movie.collect_segments( ...
%       'study_path', 'C:\EEG_Data\MovieStudy', ...
%       'StartMarker', 'start',
%       'EndMarker', 'end',
%       'expected_length', 150000);
%% ---- Parse Name–Value inputs
p = inputParser;
p.FunctionName = 'collect_segments';
addParameter(p, 'study_path', '', @(x) ischar(x) && ~isempty(x));
addParameter(p, 'searchstring', '.*\.set$', @ischar);
addParameter(p, 'recursive', true, @islogical);
addParameter(p, 'subject_parser', '(?<sub>.+)', @ischar);
addParameter(p, 'setFile', {}, @(x) iscellstr(x) || isstring(x))
addParameter(p, 'subjects_to_include', 'all', @(x) (ischar(x) && strcmpi(x, 'all')) || (isnumeric(x) && isvector(x)));

addParameter(p,'chan_include',{},@(x)iscellstr(x) || isstring(x));
addParameter(p,'chan_exclude',{},@(x)iscellstr(x) || isstring(x));

addParameter(p, 'StartMarker', '', @(s) ischar(s) || isstring(s));
addParameter(p, 'EndMarker', '', @(s) ischar(s) || isstring(s));
addParameter(p, 'PadSec', 0, @isnumeric);

% Resampling data to save length
addParameter(p, 'movie_duration_sec', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
addParameter(p, 'expected_length', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));

% Output quality information
addParameter(p, 'check_quality', false, @islogical);

addParameter(p, 'locutoff', [], @(x) isempty(x) || isscalar(x));
addParameter(p, 'hicutoff', [], @(x) isempty(x) || isscalar(x));
addParameter(p, 'csd', false, @islogical);
addParameter(p, 'csd_lambda', 1.0e-5, @isscalar);
addParameter(p, 'csd_head_radius', 10.0, @isscalar);
addParameter(p, 'csd_m', 4, @isscalar);
addParameter(p, 'hilbert_env', false, @islogical);

% Time-frequency decomposition
addParameter(p, 'tfr', false, @islogical);
addParameter(p, 'tfr_freqs', [], @(x) isempty(x) || isvector(x));
addParameter(p, 'tfr_n_cycles', [3 0.5], @isnumeric);
addParameter(p, 'tfr_winsize', 250, @isscalar);

addParameter(p, 'to_single', false, @islogical);
addParameter(p, 'save_path', '', @ischar);
addParameter(p, 'save_v7_3', true, @islogical);
addParameter(p, 'run_tag', datestr(now, 'yyyy-mm-dd_HHMMSS'), @ischar);

parse(p, varargin{:});
opt = p.Results;

if isempty(opt.setFile)
assert(~isempty(opt.study_path) && isfolder(opt.study_path), 'study_path not found.');
end
assert(~isempty(opt.StartMarker) && ~isempty(opt.EndMarker), 'StartMarker and EndMarker are required.');
assert(~(~isempty(opt.expected_length) && ~isempty(opt.movie_duration_sec)), 'Use either expected_length or movie_duration_sec, not both.');

if opt.tfr
    assert(exist('newtimef', 'file'), 'newtimef() not found. Is EEGLAB in your path?');
    assert(~isempty(opt.tfr_freqs), 'tfr_freqs must be provided when tfr=true.');
end


%% ---- Find .set files
if isempty(opt.setFile)
[paths, names] = filesearch_regexp(opt.study_path, opt.searchstring, opt.recursive);
assert(~isempty(names), 'No .set files matched searchstring in study_path.');

    % Sort files naturally to ensure consistent subject ordering
    if exist('natsort', 'file')
        [~, sort_idx] = natsort(names);
        paths = paths(sort_idx);
        names = names(sort_idx);
    else
        warning('natsort.m not found. Files will be processed in default order. For consistent subject selection, add natsort to your path.');
    end

setFiles = fullfile(paths, names);
assert(~isempty(setFiles), 'No .set files matched searchstring in study_path.');

else
    setFiles=opt.setFile;
end
% --- Apply subject selection ---
if isnumeric(opt.subjects_to_include)
    num_found = numel(setFiles);
    indices = opt.subjects_to_include;
    indices = unique(round(indices(indices > 0 & indices <= num_found)));
    assert(~isempty(indices), 'The specified ''subjects_to_include'' indices resulted in an empty list of subjects.');
    fprintf('Including %d subjects based on specified indices.\n', numel(indices));
    setFiles = setFiles(indices);
end

%% ---- Initialize output container
Out = struct();
preproc_opts = struct('locutoff', opt.locutoff, 'hicutoff', opt.hicutoff, ...
    'csd', opt.csd, 'csd_lambda', opt.csd_lambda, ...
    'csd_head_radius', opt.csd_head_radius, 'csd_m', opt.csd_m, ...
    'hilbert_env', opt.hilbert_env,...
    'check_quality', opt.check_quality);

tfr_opts = struct('enable', opt.tfr, 'freqs', opt.tfr_freqs, 'n_cycles', opt.tfr_n_cycles);

Out.meta = struct( ...
    'fs',              [], ...
    'chanlocs',        [], ...
    'start_marker',    opt.StartMarker, ...
    'end_marker',      opt.EndMarker, ...
    'padding_sec',     opt.PadSec, ...
    'expected_length', [], ... % Will be filled in later
    'preproc',         preproc_opts, ...
    'tfr',             tfr_opts, ...
    'tfr_freqs',       [], ...
    'tfr_times',       [], ...
    'created_at',      datestr(now, 'yyyy-mm-dd HH:MM:SS'), ...
    'run_tag',         opt.run_tag, ...
    'version',         1.2);

%% ---- Iterate files (per subject)
firstMetaLocked = false;
warns = {};
quality_reports = {};

for i = 1:numel(setFiles)
    fpath = setFiles{i};
        [subID, sesID] = parseSubSesFromFile(fpath, opt.subject_parser);
        if ~isempty(sesID)
            subKey = makeFieldKey(sprintf('%s-%s', subID, sesID));  % sub-2005-pre
        else
            subKey = makeFieldKey(subID);
        end

    try
        % Load
        EEG = pop_loadset(fpath);
        EEG = eeg_checkset(EEG);

        % ---- Channel selection
        if ~isempty(opt.chan_include) && ~isempty(opt.chan_exclude)
            error('Use either chan_include or chan_exclude, not both.');
        end
        if ~isempty(opt.chan_include)
            EEG = pop_select(EEG, 'channel', opt.chan_include);
            EEG = eeg_checkset(EEG);
        end
        if ~isempty(opt.chan_exclude)
            EEG = pop_select(EEG, 'nochannel', opt.chan_exclude);
            EEG = eeg_checkset(EEG);
        end

        
          % ---- Data Quality Metrics
        if opt.check_quality && ~isempty(EEG.data)
            % Calculate data quality metrics
            EEG2qc =pop_eegfiltnew(EEG, 'locutoff', 1);
            EEG2qc = eeg_checkset(EEG2qc);
            data_quality = calculate_data_quality(EEG2qc);
        else
            data_quality = struct();
        end
      
        % ---- Filtering
        if (~isempty(opt.locutoff) && opt.locutoff > 0) || (~isempty(opt.hicutoff) && opt.hicutoff > 0)
            args = {};
            if ~isempty(opt.locutoff) && opt.locutoff > 0, args = [args, {'locutoff', opt.locutoff}]; end
            if ~isempty(opt.hicutoff) && opt.hicutoff > 0, args = [args, {'hicutoff', opt.hicutoff}]; end
            EEG = pop_eegfiltnew(EEG, args{:});
            EEG = eeg_checkset(EEG);
        end




        % Crop the segment
        crop_state = prep.crop_by_markers(struct('EEG', EEG), struct( ...
            'StartMarker', opt.StartMarker, ...
            'EndMarker', opt.EndMarker, ...
            'PadSec', opt.PadSec));
        EEG_cropped = crop_state.EEG;
        crop_info = crop_state.history(end).metrics;


            
        % ---- Resample to fixed length if requested

        resample_info = struct();
        if ~isempty(opt.expected_length) || ~isempty(opt.movie_duration_sec)
            if ~isempty(opt.movie_duration_sec)
                N_ref = round(opt.movie_duration_sec * EEG_cropped.srate);
            else
                N_ref = opt.expected_length;
            end

            original_length = EEG_cropped.pnts;
            
            if original_length ~= N_ref
                % resample() works on columns, so we transpose, resample, and transpose back
                % data_resampled = resample(double(EEG_cropped.data'), N_ref, original_length)' ;
                t_old = 1:original_length;
                t_new = linspace(1, original_length, N_ref);
                data_resampled = interp1(t_old, EEG_cropped.data', t_new, 'pchip').';
            else
                data_resampled = EEG_cropped.data;
            end
            
            EEG_cropped.data = data_resampled;
            EEG_cropped.pnts = N_ref;
            
            resample_info.original_length = original_length;
            resample_info.expected_length = N_ref;
            resample_info.missing_samples = N_ref - original_length;
            
            if ~isfield(Out.meta, 'resampling_applied')
                Out.meta.resampling_applied = true;
                Out.meta.expected_length = N_ref;
            end
        end

        % ---- CSD Transformation
        if opt.csd
            if ~exist('CSD.m', 'file')
                error('CSD.m not found. Make sure the CSD toolbox is in your MATLAB path.');
            end
            montage.lab = {EEG_cropped.chanlocs.labels};
            montage.theta = [EEG_cropped.chanlocs.sph_theta];
            montage.phi = [EEG_cropped.chanlocs.sph_phi];
            [G, H] = GetGH(montage, opt.csd_m);
            EEG_cropped.data = CSD(EEG_cropped.data, G, H, opt.csd_lambda, opt.csd_head_radius);
        end

        % ---- Hilbert Amplitude Envelope
        if opt.hilbert_env
            for chan_i = 1:EEG_cropped.nbchan
                EEG_cropped.data(chan_i, :) = abs(hilbert(EEG_cropped.data(chan_i, :)));
            end
        end
        
        % ---- Time-Frequency Decomposition
        if opt.tfr
            if opt.hilbert_env
                error('Hilbert envelope was applied before TFR. This may not be intended.');
            end

            if ~isempty(opt.locutoff) && opt.locutoff > 0 || ~isempty(opt.hicutoff) && opt.hicutoff > 0
                error('Cutoffs were specified, but TFR is not implemented with cutoffs. Please remove them.');
            end

            fprintf('Running TFR for %s...\n', subID);
            % Per user insight, newtimef must be called per-channel for continuous data
            % to avoid misinterpreting the [chan x pnts] matrix.
            
            % Run the first channel to get output dimensions
            [ersp_one_chan, ~, ~, tfr_times, tfr_freqs] = newtimef(EEG_cropped.data(1,:), ...
                EEG_cropped.pnts, ...
                [EEG_cropped.xmin EEG_cropped.xmax]*1000, ...
                EEG_cropped.srate, ...
                opt.tfr_n_cycles, ...
                'winsize', 250, ...
                'freqs', opt.tfr_freqs, ...
                'baseline', NaN, ...
                'plotersp', 'off', ...
                'plotitc', 'off', ...
                'verbose', 'off');

            % Pre-allocate the full data matrix
            data = zeros(EEG_cropped.nbchan, size(ersp_one_chan,1), size(ersp_one_chan,2));
            data(1,:,:) = ersp_one_chan;

            % Loop through the rest of the channels
            for chan_idx = 2:EEG_cropped.nbchan
                [data(chan_idx,:,:)] = newtimef(EEG_cropped.data(chan_idx,:), ...
                    EEG_cropped.pnts, ...
                    [EEG_cropped.xmin EEG_cropped.xmax]*1000, ...
                    EEG_cropped.srate, ...
                    opt.tfr_n_cycles, ...
                     'winsize', opt.tfr_winsize, ...
                    'freqs', opt.tfr_freqs, ...
                    'baseline', NaN, ...
                    'plotersp', 'off', ...
                    'plotitc', 'off', ...
                    'verbose', 'off');
            end
        else
            data = EEG_cropped.data;
        end

        % Lock meta from the first processed file
        if ~firstMetaLocked
            Out.meta.fs = EEG_cropped.srate;
            Out.meta.chanlocs = EEG_cropped.chanlocs;
            if opt.tfr
                Out.meta.tfr_freqs = tfr_freqs;
                Out.meta.tfr_times = tfr_times;
            end
            firstMetaLocked = true;
        else
            if EEG_cropped.srate ~= Out.meta.fs
                warns{end+1} = sprintf('[WARN] %s: srate %g ~= meta.srate %g', subID, EEG_cropped.srate, Out.meta.fs);
            end
            if numel(EEG_cropped.chanlocs) ~= numel(Out.meta.chanlocs)
                warns{end+1} = sprintf('[WARN] %s: channel count differs from first file', subID);
            end
        end

        if opt.to_single, data = single(data); end

        % Store data
        Out.(subKey).data = data;
        Out.(subKey).crop_info = crop_info;
        if opt.tfr
            Out.(subKey).tfr_input_samples = EEG_cropped.pnts;
        end

        if ~isempty(fieldnames(data_quality))
            Out.(subKey).quality_info = data_quality;

            % For meta table
            report_row = struct2table(data_quality, 'AsArray', true);
            report_row.subject = string(subKey);
            quality_reports{end+1} = report_row;
        end

        if ~isempty(fieldnames(resample_info))
            Out.(subKey).resample_info = resample_info;
        end

    catch ME
        % Errors during processing for a subject are fatal.
        fprintf('[ERROR] Failed to process subject %s. Halting execution.\n', subID);
        rethrow(ME);
    end
end

%% ---- Assemble quality data table ----
if ~isempty(quality_reports)
    Out.meta.data_quality = vertcat(quality_reports{:});
    % Move subject column to the front
    if ismember('subject', Out.meta.data_quality.Properties.VariableNames)
        Out.meta.data_quality = movevars(Out.meta.data_quality, 'subject', 'Before', 1);
    end
end

%% ---- Save if requested
if ~isempty(opt.save_path)
    if opt.save_v7_3
        save(opt.save_path, 'Out', '-v7.3');
    else
        save(opt.save_path, 'Out');
    end
end

% Optional: print warnings
if ~isempty(warns)
    fprintf('=== Extraction warnings (%d) ===\n', numel(warns));
    fprintf('%s\n', strjoin(warns, newline));
end

end  % main function


%% ----------------- Local helpers -----------------

function [subID, sesID] = parseSubSesFromFile(fpath, parserPattern)
    [~,fname,~] = fileparts(fpath);
    m = regexp(fname, parserPattern, 'names');
    assert(~isempty(m) && isfield(m,'sub'), 'Failed to parse subject from: %s', fname);
    subID = m.sub;
    if isfield(m,'ses') && ~isempty(m.ses), sesID = m.ses; else, sesID = ''; end
end

function key = makeFieldKey(txt)
    key = lower(regexprep(txt,'[^A-Za-z0-9]','_'));
    if ~isempty(key) && isstrprop(key(1),'digit'), key = ['x' key]; end
end
