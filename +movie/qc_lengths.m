function [is_valid, keep_idx, target_len, report] = qc_lengths(counts, fs, tolerance_sec)
% QC_LENGTHS Flag sample counts outside a tolerance around their median.
%
% INPUTS:
%   counts        : Vector of sample counts (e.g., data_quality.data_point_count)
%   fs            : Sampling rate (e.g., 250)
%   tolerance_sec : Max allowed deviation in seconds (e.g., 1.0)
%
% OUTPUTS:
%   keep_idx   : Indices of subjects to KEEP
%   target_len : The calculated "Gold Standard" length (Median)
%   report     : A struct containing text for your publication and console stats

    % 1. Basic Setup
    if nargin < 3, tolerance_sec = 1.0; end
    counts = double(counts(:)); % Force column vector
    N_total = length(counts);
    
    % 2. Determine Gold Standard (Target Length)
    % Median is used because it is robust to extreme outliers (run-ons/dropouts)
    target_len = median(counts);
    
    % 3. Calculate Thresholds
    tol_samples = round(tolerance_sec * fs);
    deviations  = counts - target_len;
    abs_dev     = abs(deviations);
    
    % 4. Identify Outliers
    is_valid = abs_dev <= tol_samples;
    keep_idx = find(is_valid);
    exclude_idx = find(~is_valid);
    
    % 5. Categorize Failures (for the report)
    % "Short" = Likely packet loss
    num_short = sum(deviations < -tol_samples);
    % "Long"  = Likely buffer lag / run-on
    num_long  = sum(deviations > tol_samples);
    
    % 6. Generate Publication Text
    % We build a dynamic string based on the actual stats
    
    method_text = sprintf([...
        'Data synchronization was anchored to hardware triggers at the start of the stimulus. ' ...
        'Due to clock drift inherent in wireless EEG acquisition, recording durations varied slightly across participants ' ...
        '(Median duration = %d samples). To ensure strict temporal alignment for Time-Resolved ISC, ' ...
        'participants with duration deviations exceeding ±%.1f seconds (%d samples) were excluded as technical outliers. ' ...
        'This resulted in the exclusion of %d participants (%d due to data loss, %d due to recording run-on). ' ...
        'The remaining %d participants were linearly resampled to the median duration to correct for minor clock drift (<%.2f%%).'], ...
        target_len, ...
        tolerance_sec, ...
        tol_samples, ...
        length(exclude_idx), ...
        num_short, ...
        num_long, ...
        length(keep_idx), ...
        (tol_samples / target_len)*100);

    % 7. Console Output
    fprintf('<strong>--- Quality Control Report ---</strong>\n');
    fprintf('Total Subjects:   %d\n', N_total);
    fprintf('Target Length:    %d samples (approx %.2f min)\n', target_len, target_len/fs/60);
    fprintf('Tolerance:        +/- %d samples (%.1f sec)\n', tol_samples, tolerance_sec);
    fprintf('--------------------------------\n');
    fprintf('<strong>EXCLUDED:         %d subjects</strong>\n', length(exclude_idx));
    fprintf('  -> Too Short:   %d (Packet Loss)\n', num_short);
    fprintf('  -> Too Long:    %d (Buffer Lag)\n', num_long);
    fprintf('<strong>RETAINED:         %d subjects</strong>\n', length(keep_idx));
    fprintf('--------------------------------\n');
    
    % Pack outputs
    report.summary_text = method_text;
    report.n_excluded = length(exclude_idx);
    report.n_kept = length(keep_idx);
    report.kept_subjects_indices = keep_idx;
end
