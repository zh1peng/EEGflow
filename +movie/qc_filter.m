function Out = qc_filter(Out, varargin)
% QC_FILTER Visualize data quality metrics and flag subjects based on robust cutoffs.
%   This function takes the output from `movie.collect_segments`, which
%   should contain data quality information in `Out.meta.data_quality`,
%   and generates a visualization of these metrics. It automatically flags
%   subjects that are outliers on any given metric using a robust statistical
%   method (Median Absolute Deviation - MAD).
%
%   The function produces a figure with subplots for each quality metric,
%   showing the value for each subject as a bar. Bars are color-coded to
%   indicate whether a subject passes (green) or fails (red) the QC check
%   for that metric. Cutoffs are determined automatically based on the MAD.
%
% Input Arguments:
%   Out         - (struct) The output from `movie.collect_segments`. Must
%                 contain `Out.meta.data_quality` as a table with quality
%                 metrics and a 'subject' column.
%
% Optional Name-Value Pair Arguments:
%   'cutoff_mad' (numeric, default: 3)
%       The number of Median Absolute Deviations (MAD) from the median to
%       use as the cutoff for flagging outliers. For a given metric, a
%       subject is flagged if their value is > median + (cutoff_mad * MAD)
%       for metrics where higher is worse, or < median - (cutoff_mad * MAD)
%       for metrics where lower is worse. This is ignored for any metric
%       that has a user-defined threshold specified in 'thresholds'.
%
%   'thresholds' (struct, default: struct())
%       A struct where field names match the metric names and values are
%       the specific cutoffs to use. For any metric specified here, the
%       MAD-based calculation is skipped.
%       Example: `struct('percent_retained_by_windows', 70, 'global_field_power_std', 5)`
%
%   'metrics_to_analyze' (cellstr, default: all non-NaN metrics)
%       A cell array of strings specifying which quality metrics to include
%       in the analysis and visualization. If empty or not provided, all
%       metrics in `Out.meta.data_quality` that are not all NaN will be used.
%
%   'save_path' (char, default: '')
%       If a full path with a filename is provided (e.g., 'C:\reports\quality.png'),
%       the generated figure will be saved to that location.
%
%   'filter_data' (logical, default: true)
%       If true, the returned `Out` structure will be filtered to include
%       only subjects that pass all quality checks. If false, the original
%       `Out` structure is returned, but with the `auto_qc` table added.

%
% Output Structure:
%   The function returns the modified `Out` struct, with a new table added:
%   `Out.meta.auto_qc`: A table where rows are subjects and columns are
%   quality metrics.
%       - Each cell contains a 1 (pass) or 0 (fail).
%       - A final column `include_auto` provides an overall flag, which is 1
%         only if the subject passes all individual metric checks.
%
% Example:
%   % First, run collect_segments to get the data structure
%   MovieData = movie.collect_segments(...);
%
%   % Then, run the quality check with a custom cutoff and specific metrics
%   MovieData = movie.qc_filter(MovieData, 'cutoff_mad', 2.5, ...
%                                   'metrics_to_analyze', {'percent_bad_channels', 'global_field_power_std'});
%
%   % View the QC table
%   disp(MovieData.meta.auto_qc);
%
%   % Get a list of subjects to include
%   subjects_to_include = MovieData.meta.auto_qc.subject(MovieData.meta.auto_qc.include_auto == 1);
%
% See also: movie.collect_segments, utils.calculate_data_quality

%% 1. Parse Inputs
p = inputParser;
p.FunctionName = 'movie.qc_filter';
addRequired(p, 'Out', @(x) isstruct(x) && isfield(x, 'meta'));
addParameter(p, 'cutoff_mad', 3, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'metrics_to_analyze', {}, @iscellstr); % New parameter
addParameter(p, 'save_path', '', @ischar);
addParameter(p, 'filter_data', true, @islogical);
addParameter(p, 'thresholds', struct(), @isstruct);
parse(p, Out, varargin{:});
opt = p.Results;


%% 2. Extract Quality Data
if ~isfield(Out, 'meta') || ~isfield(Out.meta, 'data_quality') || isempty(Out.meta.data_quality)
    error('Input struct must contain `Out.meta.data_quality` table with quality information. Have you turn on check_quality when extract segmentation?');
end

% Get the quality data table
quality_data_table = Out.meta.data_quality;

% Ensure 'subject' column exists and is the first column
if ~ismember('subject', quality_data_table.Properties.VariableNames)
    error('The `Out.meta.data_quality` table must contain a ''subject'' column.');
end
if ~strcmp(quality_data_table.Properties.VariableNames{1}, 'subject')
    quality_data_table = movevars(quality_data_table, 'subject', 'Before', 1);
end

num_subjects = height(quality_data_table);
assert(num_subjects > 0, '`Out.meta.data_quality` table is empty.');

% Convert table to a struct of arrays for easier access to metric values
quality_data_struct = table2struct(quality_data_table, 'ToScalar', true);

%% 3. Determine which metrics to analyze and plot
if isempty(opt.metrics_to_analyze)
    % If not specified, analyze all non-subject metrics that are not all NaN
    metrics_to_analyze = {};
    all_possible_metrics = quality_data_table.Properties.VariableNames(2:end); % Exclude 'subject'
    for i = 1:numel(all_possible_metrics)
        metric_name = all_possible_metrics{i};
        if ~all(isnan(quality_data_struct.(metric_name)))
            metrics_to_analyze{end+1} = metric_name;
        end
    end
else
    % Use the specified metrics, but check if they exist and are not all NaN
    metrics_to_analyze = {};
    for i = 1:numel(opt.metrics_to_analyze)
        metric_name = opt.metrics_to_analyze{i};
        if ismember(metric_name, quality_data_table.Properties.VariableNames) && ~all(isnan(quality_data_struct.(metric_name)))
            metrics_to_analyze{end+1} = metric_name;
        else
            warning('Specified metric ''%s'' not found, or contains only NaN values. Skipping.', metric_name);
        end
    end
end

if isempty(metrics_to_analyze)
    warning('No valid quality metrics found to analyze or plot based on your selection.');
    return;
end

%% 4. Calculate Cutoffs and Generate Flags
qc_flags = table();
qc_flags.subject = quality_data_table.subject;
cutoffs = struct();

% Define which metrics are considered worse when their value is higher
higher_is_worse = {
                   'percent_bad_channels', 'percent_rejected_epochs', 'global_field_power_std', ...
                   'global_field_power_mean', 'amplitude_spread_1k', 'amplitude_spread_global', ...
                   'amplitude_spread_proxy', 'high_freq_noise_ratio', 'line_noise_power_50Hz', ...
                   'line_noise_power_60Hz', 'percent_rejected_by_windows'
                  };

for i = 1:numel(metrics_to_analyze)
    metric = metrics_to_analyze{i}; % This is a string like 'percent_bad_channels'
    vals = quality_data_struct.(metric); % Access values from the struct
    
    % Check if a user-defined threshold is provided for this metric
    if isfield(opt.thresholds, metric)
        cutoff = opt.thresholds.(metric);
        fprintf('Using user-defined threshold for %s: %.2f\n', metric, cutoff);
    else
        % Calculate robust stats (median and median absolute deviation)
        med = median(vals, 'omitnan');
        mad_val = custom_nanmad(vals);
        
        % Determine cutoff based on MAD
        if any(strcmpi(metric, higher_is_worse))
            cutoff = med + opt.cutoff_mad * mad_val;
        else % Lower is worse
            cutoff = med - opt.cutoff_mad * mad_val;
        end
    end

    % Determine pass/fail flags based on the cutoff
    if any(strcmpi(metric, higher_is_worse))
        pass_fail_flags = vals <= cutoff;
    else % Lower is worse
        pass_fail_flags = vals >= cutoff;
    end
    
    pass_fail_flags(isnan(vals)) = true; % Treat NaN as passing for that metric
    
    qc_flags.(metric) = pass_fail_flags;
    cutoffs.(metric) = cutoff;
end


% Add overall include/exclude flag (1 if all individual flags are 1)
metric_flags = table2array(qc_flags(:, 2:end));
qc_flags.include_auto = all(metric_flags, 2);

% Store in output struct
Out.meta.auto_qc = qc_flags;

%% 5. Create Visualization
num_plots = numel(metrics_to_analyze);
if num_plots == 0, return; end

figure('Name', 'Data Quality Check', 'Color', 'w', 'Position', [100 100 1400 400*ceil(num_plots/4)]);
sgtitle(sprintf('Data Quality Metrics (Cutoff = median +/- %.1f*MAD)', opt.cutoff_mad), 'FontSize', 16, 'FontWeight', 'bold');

for i = 1:num_plots
    metric = metrics_to_analyze{i};
    vals = quality_data_struct.(metric);
    flags = qc_flags.(metric);
    
    if num_plots == 1
        subplot(1, 1, 1); % Use a single subplot
    else
        subplot(ceil(num_plots/4), 4, i); % Original logic for multiple plots
    end
    
    pass_idx = find(flags == 1);
    fail_idx = find(flags == 0);
    
    hold on;
    if ~isempty(pass_idx), bar(pass_idx, vals(pass_idx), 'FaceColor', [0 .6 0.2], 'EdgeColor', 'none'); end
    if ~isempty(fail_idx), bar(fail_idx, vals(fail_idx), 'FaceColor', [0.8 0.2 0.1], 'EdgeColor', 'none'); end
    
    line_h = yline(cutoffs.(metric), '--r', 'LineWidth', 1.5);

    current_ylim = ylim;
    new_ylim_top = current_ylim(2) * 1.2; % Increase top by 20; 
    ylim([current_ylim(1), new_ylim_top]);

    legend(line_h, sprintf('Cutoff (%.2f)', cutoffs.(metric)), 'Location', 'northeast', 'Box', 'off');
    
    hold off;
    
    title(strrep(metric, '_', ' '), 'FontWeight', 'normal');
    ylabel('Value');
    xlabel('Subject');
    xlim([0 num_subjects+1]); % Use num_subjects from the table height
    % set(gca, 'XTick', 1:num_subjects, 'XTickLabel', strrep(quality_data_table.subject, 'sub_', ''), 'XTickLabelRotation', 90);
    % set Xtic off
    set(gca, 'XTickLabel', []);
    grid on;
end

%% 6. Save figure if requested
if ~isempty(opt.save_path)
    fprintf('Saving quality report figure to: %s\n', opt.save_path);
    exportgraphics(gcf, opt.save_path, 'Resolution', 150);
end



% 7. Filter subjects in the output structure if requested
if opt.filter_data

    fprintf('Filtering subjects based on quality check...\n');
    
    % Get the list of subject keys that passed the quality check
    subjects_to_keep_table = qc_flags(qc_flags.include_auto == 1, :);
    subjects_to_keep_keys = subjects_to_keep_table.subject;

    % Create a new structure to hold the filtered data
    filtered_Out = struct();
    filtered_Out.meta = Out.meta; % Copy the original meta (which now includes auto_qc)
    
    % Store the filtered data quality table
    filtered_Out.meta.data_quality_after_qc = quality_data_table(qc_flags.include_auto == 1, :);

    % Iterate through subjects_to_keep_keys and copy their data
    for i = 1:numel(subjects_to_keep_keys)
        sub_key = subjects_to_keep_keys{i};
        if isfield(Out, sub_key)
            filtered_Out.(sub_key) = Out.(sub_key);
        end
    end
    Out = filtered_Out; % Overwrite the original Out with the filtered version
    fprintf('Retained %d subjects out of %d original subjects.\n', numel(subjects_to_keep_keys), num_subjects);
else
    % If not filtering, ensure data_quality_after_qc is not present or is empty
    % This is to avoid confusion if the user later checks for it.
    if isfield(Out.meta, 'data_quality_after_qc')
        Out.meta = rmfield(Out.meta, 'data_quality_after_qc');
    end
end


end

function m = custom_nanmedian(x)
    x = x(~isnan(x));
    if isempty(x)
        m = NaN;
        return;
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
