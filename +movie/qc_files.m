function [quality_data_table, qc_table] = qc_files(varargin)
%QC_FILES  Compute per-file EEG quality metrics with optional parallelism.
%
%   [quality_data_table, qc_table] = qc_files('Name',Value,...)
%
%   PURPOSE
%     Scan a study folder for EEGLAB .set files, compute a panel of data
%     quality metrics for each file (via your `calculate_data_quality`),
%     and flag outliers using Median Absolute Deviation (MAD) cutoffs.
%     Results include the *full file path* for easy downstream selection,
%     and an overall `include_auto` flag per subject.
%
%   KEY FEATURES
%     • Optional parallel processing (default ON) with graceful fallback.
%     • Robust outlier detection using median ± MAD (metric-wise).
%     • Full file path saved in both output tables for quick subsetting.
%     • Quick visualization of selected metrics with cutoff overlays.
%
%   INPUTS (Name–Value pairs)
%     'study_path'         (char)   REQUIRED. Root directory to search.
%     'searchstring'       (char)   Regex to match files. Default '.*\.set$'
%     'recursive'          (logical)Search subfolders. Default true
%     'subject_parser'     (char)   Regex with (?<sub>...) to extract subject ID.
%                                   Default '(?<sub>.+)'
%     'subjects_to_include'(vector|'all') Indices (after natural sort) or 'all'.
%                                   Default 'all'
%
%     QC / Metrics
%     'qc_locutoff'        (scalar|[]) High-pass for QC evaluation only (Hz).
%                                   Default 1   (set [] to skip filtering)
%                                   Applies to all signal-based QC metrics;
%                                   loaded files are not overwritten.
%     'metrics_to_analyze' (cellstr) Metrics to include in MAD-based flagging.
%                                   Default: all numeric columns found
%     'cutoff_mad'         (scalar) # of MADs from median to set cutoff. Default 3
%     'thresholds'         (struct) Per-metric manual cutoffs that override MAD.
%                                   Example: thresholds.percent_bad_channels = 20;
%
%     Execution / Output
%     'parallel'           (logical)Enable parfor. Default true
%     'engine'             (char)   'parfor' (default) or 'serial'
%     'save_path'          (char)   File path to save the QC figure (optional)
%
%   OUTPUTS
%     quality_data_table : Table (one row per file) with:
%         • subject  : parsed subject key (string)
%         • file     : full path to the .set file (string)
%         • <metrics>: numeric quality metrics from calculate_data_quality
%
%     qc_table : Table with pass/fail flags and inclusion summary:
%         • subject      : same as above
%         • file         : full path (same order as quality_data_table)
%         • <metric>     : logical column per analyzed metric (1=pass, 0=fail)
%         • include_auto : logical; true if all selected metrics passed
%
%   METHOD
%     1) Discover .set files by regex (optionally recursive), natural-sort them,
%        and optionally subset by indices via 'subjects_to_include'.
%     2) For each file, load with EEGLAB, optionally high-pass at 'qc_locutoff',
%        then compute metrics using your `calculate_data_quality`.
%     3) For each selected metric, compute a MAD-based cutoff (median ± k*MAD).
%        For metrics where “higher is worse” (e.g., % bad channels), values
%        above the cutoff fail; for others, values below the cutoff fail.
%        You can override any cutoff via the 'thresholds' struct.
%     4) Build a flags table and an overall `include_auto` per subject.
%     5) Plot per-metric bar charts with cutoff lines; optionally save the figure.
%
%   DEPENDENCIES
%     • EEGLAB: pop_loadset, pop_eegfiltnew, eeg_checkset
%     • Your function: calculate_data_quality(EEG)
%     • Helper: filesearch_regexp (for file discovery)
%     • Optional: natsort (for natural filename ordering)
%     • Parallel Computing Toolbox (optional; function falls back to serial)
%
%   USAGE EXAMPLES
%
%     % 1) Basic QC over a study (parallel ON by default)
%     [qdat, qc] = movie.qc_files( ...
%         'study_path', '/data/HBN_EEG_BIDS', ...
%         'searchstring', '^sub.*\eeg_prep\.set$');
%
%     % Files to keep after QC:
%     setFiles_keep = qdat.file(qc.include_auto);
%
%     % 2) Process a subset of subjects (first 100), save figure
%     [qdat, qc] = movie.qc_files( ...
%         'study_path', '/data/HBN_EEG_BIDS', ...
%         'subjects_to_include', 1:100, ...
%         'save_path', '/tmp/qc_overview.png');
%     setFiles_keep = qdat.file(qc.include_auto);
%
%     % 3) Use specific metrics only + manual threshold override
%     thresholds.percent_bad_channels = 20;  % pass if ≤ 20%
%     [qdat, qc] = movie.qc_files( ...
%         'study_path', '/data/HBN_EEG_BIDS', ...
%         'metrics_to_analyze', {'percent_bad_channels','percent_rejected_by_windows'}, ...
%         'thresholds', thresholds);
%
%     % 4) Disable parallel, skip QC high-pass
%     [qdat, qc] = movie.qc_files( ...
%         'study_path', '/data/HBN_EEG_BIDS', ...
%         'parallel', false, ...
%         'qc_locutoff', []);
%
%     % 5) Pipeline: QC → streaming CorrCA with the kept files
%     [qdat, qc] = movie.qc_files('study_path','/data/HBN_EEG_BIDS','searchstring','^sub.*\eeg_prep\.set$');
%     setFiles_keep = qdat.file(qc.include_auto);
%     [W,ISC,Y,A] = movie.run_corrca_stream( ...
%         'setFile', setFiles_keep, ...
%         'StartMarker', 'video_start', 'EndMarker', 'video_stop', ...
%         'locutoff', 1, 'hicutoff', 4, 'movie_duration_sec', 203.074, ...
%         'parallel', true, 'engine', 'parfor', 'shrinkage', 0.1, 'tsvd', 3);
%
%   NOTES
%     • Treat NaNs as “pass” by default (uninformative). You can predefine
%       explicit thresholds for such metrics in 'thresholds'.
%     • The set of “higher-is-worse” metrics is hard-coded; adjust it in the
%       function if your metric semantics differ.
%     • Parallelism is at the file level (independent per subject). Avoid
%       running another nested parpool around this function.

%% 1) Parse inputs
p = inputParser;
p.FunctionName = 'movie.qc_files';
addParameter(p, 'study_path', '', @ischar);
addParameter(p, 'searchstring', '.*\.set$', @ischar);
addParameter(p, 'recursive', true, @islogical);
addParameter(p, 'subject_parser', '(?<sub>.+)', @ischar);
addParameter(p, 'subjects_to_include', 'all', @(x) (ischar(x) && strcmpi(x, 'all')) || (isnumeric(x) && isvector(x)));
addParameter(p, 'cutoff_mad', 3, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'metrics_to_analyze', {}, @iscellstr);
addParameter(p, 'chan_exclude', {}, @iscellstr);
addParameter(p, 'save_path', '', @ischar);
addParameter(p, 'thresholds', struct(), @isstruct);
addParameter(p, 'parallel', true, @islogical);         % << NEW
addParameter(p, 'engine', 'parfor', @(s)ischar(s));    % << NEW
addParameter(p, 'qc_locutoff', 1, @(x) isempty(x) || (isscalar(x) && x>=0)); % << optional
parse(p, varargin{:});
opt = p.Results;

assert(~isempty(opt.study_path), 'You must provide a ''study_path''.');

%% 2) Discover files
fprintf('Scanning %s for .set files...\n', opt.study_path);
[paths, names] = filesearch_regexp(opt.study_path, opt.searchstring, opt.recursive);
assert(~isempty(names), 'No .set files matched searchstring in study_path.');

if exist('natsort', 'file'), [~, sort_idx] = natsort(names); paths = paths(sort_idx); names = names(sort_idx); end
setFiles = fullfile(paths, names);

% Subject selection
if isnumeric(opt.subjects_to_include)
    num_found = numel(setFiles);
    indices = opt.subjects_to_include;
    indices = unique(round(indices(indices > 0 & indices <= num_found)));
    assert(~isempty(indices), 'The specified subjects_to_include indices resulted in an empty list of subjects.');
    fprintf('Including %d subjects based on specified indices.\n', numel(indices));
    setFiles = setFiles(indices);
end

N = numel(setFiles);
assert(N>0, 'No files to process after selection.');

%% 3) Compute QC metrics (parallel by default)
quality_reports = cell(N,1);

usePar = opt.parallel && havePCT();
if usePar
    pool = gcp('nocreate'); if isempty(pool), parpool; end
    fprintf('Computing QC in parallel (N=%d)...\n', N);
    parfor i = 1:N
        quality_reports{i} = qc_one_file(setFiles{i}, opt);
    end
else
    fprintf('Computing QC serially (N=%d)...\n', N);
    for i = 1:N
        quality_reports{i} = qc_one_file(setFiles{i}, opt);
    end
end

% Concatenate into a table
quality_data_table = vertcat(quality_reports{:});

% Ensure 'subject' first, 'file' second
if ~ismember('subject', quality_data_table.Properties.VariableNames)
    error('Quality data table must contain a ''subject'' column.');
end
if ~strcmp(quality_data_table.Properties.VariableNames{1}, 'subject')
    quality_data_table = movevars(quality_data_table, 'subject', 'Before', 1);
end
if ismember('file', quality_data_table.Properties.VariableNames)
    if ~strcmp(quality_data_table.Properties.VariableNames{2}, 'file')
        quality_data_table = movevars(quality_data_table, 'file', 'After', 'subject');
    end
end

num_subjects = height(quality_data_table);
assert(num_subjects > 0, 'Quality data table is empty.');

%% 4) Decide metrics to analyze (numeric vars only)
% By default, take all numeric columns (skip 'subject'/'file')
numericMask = varfun(@isnumeric, quality_data_table, 'OutputFormat', 'uniform');
numericVars = quality_data_table.Properties.VariableNames(numericMask);

if isempty(opt.metrics_to_analyze)
    metrics_to_analyze = numericVars;  % numeric only
else
    metrics_to_analyze = opt.metrics_to_analyze;
end

if isempty(metrics_to_analyze)
    warning('No numeric quality metrics found to analyze.');
    qc_table = table();
    return;
end

%% 5) MAD cutoffs + pass/fail flags
qc_table = table();
qc_table.subject = quality_data_table.subject;
qc_table.file    = quality_data_table.file;   % << include path in qc table too

cutoffs = struct();
higher_is_worse = {'percent_bad_channels', 'percent_rejected_epochs', 'global_field_power_std','global_field_power_mean', ...
                   'amplitude_spread_1k','amplitude_spread_global', 'high_freq_noise_ratio', 'line_noise_power_50Hz', ...
                   'line_noise_power_60Hz', 'percent_rejected_by_windows','data_point_count'};

for i = 1:numel(metrics_to_analyze)
    metric = metrics_to_analyze{i};
    if ~ismember(metric, quality_data_table.Properties.VariableNames), continue; end
    vals = quality_data_table.(metric);
    if ~isnumeric(vals), continue; end

    % User-specified threshold overrides
    if isfield(opt.thresholds, metric)
        cutoff = opt.thresholds.(metric);
        fprintf('Using user-defined threshold for %s: %.4g\n', metric, cutoff);
    else
        med = custom_nanmedian(vals);
        mad_val = custom_nanmad(vals);
        if any(strcmpi(metric, higher_is_worse))
            cutoff = med + opt.cutoff_mad * mad_val;
        else
            cutoff = med - opt.cutoff_mad * mad_val;
        end
    end

    if any(strcmpi(metric, higher_is_worse))
        pass_fail_flags = vals <= cutoff;
    else
        pass_fail_flags = vals >= cutoff;
    end

    pass_fail_flags(isnan(vals)) = true;  % treat NaN as pass (uninformative)
    qc_table.(metric) = pass_fail_flags;
    cutoffs.(metric) = cutoff;
end

% Overall include flag = all metric flags (ignore first two meta cols)
if width(qc_table) > 2
    metric_flags = table2array(qc_table(:, 3:end));
    qc_table.include_auto = all(metric_flags, 2);
else
    qc_table.include_auto = true(height(qc_table),1);
end

%% 6) Visualization
metrics_to_plot = metrics_to_analyze; % already numeric
num_plots = numel(metrics_to_plot);
if num_plots > 0
    figure('Name', 'Data Quality Check', 'Color', 'w', 'Position', [100 100 1400 400*ceil(num_plots/4)]);
    sgtitle(sprintf('Data Quality Metrics (Cutoff = median \\pm %.1f*MAD)', opt.cutoff_mad), ...
            'FontSize', 16, 'FontWeight', 'bold');

    for i = 1:num_plots
        metric = metrics_to_plot{i};
        if ~isfield(cutoffs, metric), continue; end
        vals = quality_data_table.(metric);
        flags = qc_table.(metric);

        if num_plots == 1
            subplot(1, 1, 1);
        else
            subplot(ceil(num_plots/4), 4, i);
        end

        pass_idx = find(flags == 1);
        fail_idx = find(flags == 0);

        hold on;
        if ~isempty(pass_idx), bar(pass_idx, vals(pass_idx), 'FaceColor', [0 .6 0.2], 'EdgeColor', 'none'); end
        if ~isempty(fail_idx), bar(fail_idx, vals(fail_idx), 'FaceColor', [0.8 0.2 0.1], 'EdgeColor', 'none'); end

        line_h = yline(cutoffs.(metric), '--r', 'LineWidth', 1.5);

        current_ylim = ylim;
        new_ylim_top = current_ylim(2) * 1.2;
        ylim([current_ylim(1), new_ylim_top]);

        legend(line_h, sprintf('Cutoff (%.3g)', cutoffs.(metric)), 'Location', 'northeast', 'Box', 'off');
        hold off;

        title(strrep(metric, '_', ' '), 'FontWeight', 'normal');
        ylabel('Value'); xlabel('Subject');
        xlim([0 num_subjects+1]);
        set(gca, 'XTickLabel', []);
        grid on;
    end
end

%% 7) Save figure if requested
if ~isempty(opt.save_path)
    fprintf('Saving quality report figure to: %s\n', opt.save_path);
    exportgraphics(gcf, opt.save_path, 'Resolution', 150);
end

end % ===== main =====


%% ----------------- Helpers -----------------

function row = qc_one_file(fpath, opt)
    % Per-file QC wrapper returning a 1-row table with metrics + subject + file
    try
        [subID, sesID] = parseSubSesFromFile(fpath, opt.subject_parser);
        if ~isempty(sesID)
            subKey = makeFieldKey(sprintf('%s-%s', subID, sesID));  % sub-2005-pre
        else
            subKey = makeFieldKey(subID);
        end

        EEG = pop_loadset(fpath);

        if ~isempty(EEG.data)
            if ~isempty(opt.qc_locutoff) && opt.qc_locutoff > 0
                EEG2qc = pop_eegfiltnew(EEG, 'locutoff', opt.qc_locutoff);
                EEG2qc = eeg_checkset(EEG2qc);
            else
                EEG2qc = EEG;
            end
            data_quality = calculate_data_quality(EEG2qc, 'chan_exclude', opt.chan_exclude);
        else
            data_quality = struct();
        end

        row = struct2table(data_quality, 'AsArray', true);
        row.subject = string(subKey);
        row.file    = string(fpath);

        % Put subject/file first for readability
        row = movevars(row, 'subject', 'Before', 1);
        if ismember('file', row.Properties.VariableNames)
            row = movevars(row, 'file', 'After', 'subject');
        end
    catch ME
        warning('QC failed for %s: %s', fpath, ME.message);
        % Return a minimal row so concatenation succeeds
        row = table(string(makeFieldKey("bad_" + string(java.util.UUID.randomUUID))),...
                    string(fpath),...
                    'VariableNames', {'subject','file'});
    end
end

function tf = havePCT()
    tf = license('test','Distrib_Computing_Toolbox') && ~isempty(ver('parallel'));
end

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

function m = custom_nanmedian(x)
    x = x(~isnan(x));
    if isempty(x)
        m = NaN; return;
    end
    x = sort(x);
    n = length(x);
    if mod(n, 2) == 1
        m = x((n + 1) / 2);
    else
        m = (x(n / 2) + x(n / 2 + 1)) / 2;
    end
end

function m = custom_nanmad(x)
    med = custom_nanmedian(x);
    m = custom_nanmedian(abs(x - med));
end
