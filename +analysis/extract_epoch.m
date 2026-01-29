function Out = extract_epoch(varargin)
% EXTRACT_STUDY_EPOCH  Build a single study-level epoch container from many EEGLAB .set files.
%   This function automates the process of finding EEGLAB .set files, applying
%   a series of optional preprocessing steps (filtering, resampling, etc.),
%   and extracting epochs around specified event markers. The result is a
%   single, well-structured MATLAB struct that is easy to analyze.
%
% Output Structure:
%   The output is a single struct `Out` with two main components:
%   1. Out.meta: A struct containing shared information across all subjects
%      and conditions. This includes:
%       .fs              - Sampling rate of the processed data.
%       .srate           - (Same as fs) Sampling rate.
%       .times           - A vector of time points for the epochs (in ms).
%       .chanlocs        - Channel locations structure from the first subject.
%       .epoch_window_ms - The [start, end] time window used for epoching.
%       .baseline_ms     - The [start, end] time window used for baseline correction.
%       .conditions      - A cell array of condition names.
%       .trialN          - A table summarizing trial counts per subject/condition.
%       .created_at      - Timestamp of when the extraction was run.
%       .run_tag         - A user-defined tag for this specific extraction run.
%
%   2. Out.sub_...: A series of dynamically named fields for each subject
%      (e.g., Out.sub_001, Out.sub_S02). Each subject field is itself a struct
%      containing data for each condition, for example:
%       .x_cond1 (e.g. .x_target) - A [channels x time x trials] matrix.
%       .x_cond2 (e.g. .x_nontarget) - Another data matrix for a different condition.
%
% Name-Value Pair Arguments:
%   'study_path' (char, REQUIRED)
%       The absolute path to the root directory containing the .set files.
%
%   'markers' (cellstr/string, REQUIRED)
%       A cell array of event marker strings to epoch around (e.g., {'S 10', 'S 20'}).
%
%   'searchstring' (char, default: '.*\.set$')
%       A regular expression to find specific .set files within the study_path.
%
%   'recursive' (logical, default: true)
%       If true, searches for files in subdirectories of study_path.
%
%   'subject_parser' (char, default: '(?<sub>.+)')
%       A regular expression with a named token '(?<sub>...)' to extract a unique
%       subject ID from each filename. An optional '(?<ses>...)' token can also be used.
%
%   'chan_include' (cellstr/string, default: {})
%       A list of channel labels to *include*. All other channels will be removed.
%       Cannot be used at the same time as 'chan_exclude'.
%
%   'chan_exclude' (cellstr/string, default: {})
%       A list of channel labels to *exclude*. All other channels will be kept.
%       Cannot be used at the same time as 'chan_include'.
%
%   'aliases' (2-column cell, default: [])
%       A mapping to rename markers to more readable condition names.
%       Example: {'S 10', 'target'; 'S 20', 'nontarget'}.
%
%   'epoch_window' (1x2 double, default: [-1000 2000])
%       The time window in milliseconds [start, end] relative to the event marker.
%
%   'baseline' (1x2 double, default: [])
%       The baseline period in milliseconds [start, end] for pop_rmbase.
%       If empty, baseline correction is skipped.
%
%   'locutoff' (scalar, default: [])
%       High-pass filter cutoff frequency in Hz. Skips if empty.
%
%   'hicutoff' (scalar, default: [])
%       Low-pass filter cutoff frequency in Hz. Skips if empty.
%
%   'resample' (scalar, default: [])
%       The target sampling rate in Hz. Skips if original srate matches or if empty.
%
%   'reference' (char, default: 'none')
%       Rereferencing scheme. Currently supports 'avg' for average reference.
%
%   'to_single' (logical, default: false)
%       If true, casts the output data matrices to the 'single' data type to save memory.
%
%   'save_path' (char, default: '')
%       If provided, the final 'Out' struct is saved to this full path.
%
%   'save_v7_3' (logical, default: true)
%       If saving, use the '-v7.3' flag to support larger files. Set to false for
%       compatibility with older MATLAB versions if data is small.
%
%   'run_tag' (char, default: timestamp)
%       A custom string tag to identify this extraction run, stored in Out.meta.
%
% Examples:
%
%   % Example 1: Basic Extraction
%   % Extracts epochs for two markers from all .set files in a directory.
%   Out1 = study.extract_epoch( ...
%       'study_path', 'C:\\EEG_Data\\Study1',
%       'markers', {'stim_A', 'stim_B'});
%
%   % Example 2: Preprocessing and Aliases
%   % Applies filtering and resampling, and renames markers to conditions.
%   Out2 = study.extract_epoch( ...
%       'study_path', 'C:\\EEG_Data\\Study1',
%       'markers', {'S11', 'S12'},
%       'aliases', {'S11', 'target'; 'S12', 'nontarget'},
%       'locutoff', 0.5,
%       'hicutoff', 40,
%       'resample', 500,
%       'baseline', [-200, 0]);
%
%   % Example 3: Channel Selection and Saving
%   % Extracts only 10 specified channels and saves the result.
%   frontal_chans = {'Fp1', 'Fp2', 'Fz', 'F3', 'F4', 'F7', 'F8'};
%   Out3 = study.extract_epoch( ...
%       'study_path', 'C:\\EEG_Data\\Study1',
%       'markers', {'cue'},
%       'chan_include', frontal_chans,
%       'save_path', 'C:\\EEG_Data\\Study1\\processed\\frontal_cue_epochs.mat',
%       'run_tag', 'frontal_analysis_v1');
%
%   % Example 4: Advanced Subject Parsing (BIDS-like)
%   % Uses a regex to extract subject and session from BIDS-style filenames
%   % like 'sub-01_ses-pre_task-rest_eeg.set'.
%   Out4 = study.extract_epoch( ...
%       'study_path', 'C:\\EEG_Data\\BIDS_Study',
%       'searchstring', '_eeg\.set$',
%       'subject_parser', '(?<sub>sub-\d+)_<ses>ses-\w+)', ...
%       'markers', {'response'});
% 
%  % Example 5 [tested!]
% subject_parser = '(?<sub>sub-\w+)_ses-(?<ses>\w+)_task-(?<task>\w+)_run-(?<run>\w+)_eeg_prep';
% Out = study.extract_epoch( ...
%       'study_path', '/media/NAS/EEGdata/METH/derivatives/prep_mid', ...
%       'searchstring', 'sub-.*\_task-mid_run-1_eeg_prep.set$', ...
%       'subject_parser',subject_parser , ...
%       'markers', {'C101'});


%% ---- Parse Name–Value inputs
p = inputParser; p.FunctionName = 'extract_study_epoch';
addParameter(p,'study_path','',@(x)ischar(x)&&~isempty(x));
addParameter(p,'searchstring','.*\.set$',@ischar);
addParameter(p,'recursive',true,@islogical);
addParameter(p,'subject_parser','(?<sub>.+)',@ischar);

addParameter(p,'chan_include',{},@(x)iscellstr(x) || isstring(x));
addParameter(p,'chan_exclude',{},@(x)iscellstr(x) || isstring(x));

addParameter(p,'markers',{},@(x)iscellstr(x) || isstring(x));
addParameter(p,'aliases',[],@(x)isempty(x) || (iscell(x)&&size(x,2)==2));  % simple 2-col

addParameter(p,'epoch_window',[-1000 2000],@(x)isnumeric(x)&&numel(x)==2); % ms
addParameter(p,'baseline',[],@(x)isnumeric(x) && (isempty(x)||numel(x)==2)); % ms

addParameter(p,'locutoff',[],@(x)isempty(x)||isscalar(x));
addParameter(p,'hicutoff',[],@(x)isempty(x)||isscalar(x));
addParameter(p,'resample',[],@(x)isempty(x)||isscalar(x));
addParameter(p,'reference','none',@(x)ischar(x)&&~isempty(x));

addParameter(p,'to_single',false,@islogical);
addParameter(p,'save_path','',@ischar);
addParameter(p,'save_v7_3',true,@islogical);
addParameter(p,'run_tag',datestr(now,'yyyy-mm-dd_HHMMSS'),@ischar);

parse(p,varargin{:});
opt = p.Results;

assert(~isempty(opt.study_path)&&isfolder(opt.study_path), 'study_path not found.');
assert(~isempty(opt.markers), 'markers is required.');
markers = cellstr(opt.markers);

% ---- Normalize aliases into two simple parallel lists (no containers.Map)
[alias_mk, alias_cond] = normalizeAliasPairs(opt.aliases);

%% ---- Find .set files (use filesearch_regexp)
[paths, names] = filesearch_regexp(opt.study_path, opt.searchstring, opt.recursive);
setFiles = fullfile(paths, names);
assert(~isempty(setFiles), 'No .set files matched searchstring in study_path.');

%% ---- Initialize output container
conds = sort(unique(lower(resolveMany(markers, alias_mk, alias_cond))));
Out = struct();
Out.meta = struct( ...
    'fs',              [], ...
    'srate',           [], ...
    'times',           [], ...
    'chanlocs',        [], ...
    'epoch_window_ms', opt.epoch_window, ...
    'baseline_ms',     opt.baseline, ...
    'preproc',         struct('locutoff',opt.locutoff,'hicutoff',opt.hicutoff, ...
                              'resample',opt.resample,'reference',opt.reference), ...
    'created_at',      datestr(now,'yyyy-mm-dd HH:MM:SS'), ...
    'run_tag',         opt.run_tag, ...
    'version',         1);
Out.meta.conditions = conds;

%% ---- Iterate files (per subject)
firstMetaLocked = false;
warns = {};

% summary collectors
summary_sub  = {};
summary_cond = {};
summary_n    = [];
summary_file = {};

for i = 1:numel(setFiles)
    fpath = setFiles{i};
        [subID, sesID] = parseSubSesFromFile(fpath, opt.subject_parser);
        if ~isempty(sesID)
            subKey = makeFieldKey(sprintf('%s-%s', subID, sesID));  % sub-2005-pre
        else
            subKey = makeFieldKey(subID);
        end

    if ~isfield(Out, subKey)
        Out.(subKey) = struct();   % no subject_id/session fields
    end

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

    % ---- Reference (inline)
    if ~isempty(opt.reference) && ~strcmpi(opt.reference,'none')
        switch lower(opt.reference)
            case 'avg'
                EEG = pop_reref(EEG, []);
            otherwise
                warning('Unknown reference mode "%s" (using none).', opt.reference);
        end
        EEG = eeg_checkset(EEG);
    end

    % ---- Filter (inline)
    if ( ~isempty(opt.locutoff) && opt.locutoff>0 ) || ( ~isempty(opt.hicutoff) && opt.hicutoff>0 )
        args = {};
        if ~isempty(opt.locutoff) && opt.locutoff>0, args = [args, {'locutoff', opt.locutoff}]; end
        if ~isempty(opt.hicutoff) && opt.hicutoff>0, args = [args, {'hicutoff', opt.hicutoff}]; end
        EEG = pop_eegfiltnew(EEG, args{:});
        EEG = eeg_checkset(EEG);
    end

    % ---- Resample (inline)
    if ~isempty(opt.resample) && opt.resample>0 && EEG.srate~=opt.resample
        EEG = pop_resample(EEG, opt.resample);
        EEG = eeg_checkset(EEG);
    end

    % Lock meta from the first processed file
    if ~firstMetaLocked
        Out.meta.fs       = EEG.srate;
        Out.meta.srate    = EEG.srate;
        Out.meta.chanlocs = EEG.chanlocs;
        firstMetaLocked   = true;
    else
        if EEG.srate ~= Out.meta.fs
            warns{end+1} = sprintf('[WARN] %s: srate %g != meta.fs %g', subKey, EEG.srate, Out.meta.fs);
        end
        if numel(EEG.chanlocs) ~= numel(Out.meta.chanlocs)
            warns{end+1} = sprintf('[WARN] %s: channel count differs from first file', subKey);
        end
    end

    % Per-marker epoch loop
    for m = 1:numel(markers)
        mk       = markers{m};
        condName = resolveAlias(mk, alias_mk, alias_cond);
        condKey  = makeFieldKey(condName);

        try
            EEGep = pop_epoch(EEG, {mk}, opt.epoch_window/1000);  % ms -> s
            EEGep = eeg_checkset(EEGep);

            if ~isempty(opt.baseline)
                EEGep = pop_rmbase(EEGep, opt.baseline, []);      % ms
            end

            if isempty(Out.meta.times) && isfield(EEGep,'times')
                Out.meta.times = EEGep.times;
            end

            data = EEGep.data;                                    % chan × time × trial
            if opt.to_single, data = single(data); end

            % ---- FLAT storage: only data
            Out.(subKey).(condKey) = data;


            % ---- add to summary
            summary_sub{end+1,1}  = subKey; 
            summary_cond{end+1,1} = condKey;
            summary_n(end+1,1)    = size(data,3);
            summary_file{end+1,1} = fpath;

        catch ME
            warns{end+1} = sprintf('[WARN] %s / %s: %s', subKey, condName, ME.message);
            Out.(subKey).(condKey) = [];
            % add zero-row to summary
            summary_sub{end+1,1}  = subKey;
            summary_cond{end+1,1} = condKey;
            summary_n(end+1,1)    = 0;
            summary_file{end+1,1} = fpath;
        end
    end
end


% ==== build WIDE summary table (one row per subject; cols = conditions) ====
% Tall table first
T = table(summary_sub, summary_cond, summary_n, summary_file, ...
    'VariableNames', {'sub','condition','n','file'});

% Pivot trial counts to wide by condition
Tw = unstack(T(:, {'sub','condition','n'}), 'n', 'condition', 'GroupingVariables', 'sub');

% Ensure all expected condition columns exist (even if some subjects lack them)
allConds = conds(:)';  % from earlier
for k = 1:numel(allConds)
    vn = allConds{k};
    if ~ismember(vn, Tw.Properties.VariableNames)
        Tw.(vn) = zeros(height(Tw),1);
    end
end

% Order columns: sub, <conds...>
Tw = Tw(:, ['sub', allConds]);

% One file path per subject (first seen) — robust across MATLAB versions
[uniqSubs, ia] = unique(T.sub, 'stable');
firstFiles     = T.file(ia);
F = table(uniqSubs, firstFiles, 'VariableNames', {'sub','file'});

% Join files onto wide table
Tw = outerjoin(Tw, F, 'Keys', 'sub', 'MergeKeys', true);

% Replace missing trial counts with 0 (defensive)
Tw{:, allConds} = fillmissing(Tw{:, allConds}, 'constant', 0);

% Attach to output
Out.meta.trialN = Tw;

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
    fprintf('=== Extraction warnings (%%d) ===\n', numel(warns));
    fprintf('%s\n', strjoin(warns,newline));
end

end  % main function


%% ----------------- Local helpers (kept minimal & readable) -----------------

function [alias_mk, alias_cond] = normalizeAliasPairs(aliases)
% Accepts [] or a 2-col cell {marker, condition}; returns two cell arrays.
    if isempty(aliases)
        alias_mk = {}; alias_cond = {};
        return;
    end
    if iscell(aliases) && size(aliases,2)==2
        alias_mk   = cellstr(aliases(:,1));
        alias_cond = cellstr(aliases(:,2));
        return;
    end
    error('aliases must be a 2-col cell {marker, condition}.');
end

function out = resolveMany(markers, alias_mk, alias_cond)
    out = cell(size(markers));
    for i=1:numel(markers)
        out{i} = resolveAlias(markers{i}, alias_mk, alias_cond);
    end
end

function name = resolveAlias(marker, alias_mk, alias_cond)
% If marker exists in alias list (case-insensitive), use the mapped condition; else lower(marker).
    if ~isempty(alias_mk)
        idx = find(strcmpi(marker, alias_mk), 1, 'first');
        if ~isempty(idx)
            name = alias_cond{idx};
            name = lower(name);
            return;
        end
    end
    name = lower(marker);
end

function [subID, sesID] = parseSubSesFromFile(fpath, parserPattern)
    [~,fname,~] = fileparts(fpath);
    m = regexp(fname, parserPattern, 'names','once');
    assert(~isempty(m) && isfield(m,'sub'), 'Failed to parse subject from: %s', fname);
    subID = m.sub;
    if isfield(m,'ses') && ~isempty(m.ses), sesID = m.ses; else, sesID = ''; end
end

function key = makeFieldKey(txt)
    key = lower(regexprep(txt,'[^A-Za-z0-9]','_'));
    if ~isempty(key) && isstrprop(key(1),'digit'), key = ['x' key]; end
end