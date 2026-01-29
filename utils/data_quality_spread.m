function quality_index = data_quality_spread(EEG)
    % data_quality_spread - Computes a simple proxy for EEG data quality.
    %
    % Description:
    %   This function estimates the quality of EEG data based on the standard deviation 
    %   (spread) of the EEG signal. It uses a subset of the data for quick computation.
    %   The output is an approximate "spacing value" that reflects the general amplitude 
    %   spread of the EEG channels. Larger values typically indicate noisier or lower-quality data.
    %
    % Inputs:
    %   EEG - EEG structure containing the data (EEG.data: [channels x time x trials])
    %
    % Outputs:
    %   quality_index - A single numeric value that approximates the EEG data quality.
    %
    % Notes:
    %   - This is a proxy metric and does not directly evaluate signal-to-noise ratio (SNR).
    %   - It uses the standard deviation of EEG data to approximate "spread."
    %   - Excludes extreme channels during the computation by trimming outliers.
    %
    % Usage Example:
    %   quality_index = data_quality_spread(EEG);
    %   fprintf('Quality Index: %f\n', quality_index);
    % This is modified from the original code in EEGlab.
    % Author: Zhipeng Cao, 2024 (zhipeng30@foxmail.com)
    % Updated: 2024
    
    % Check input
    if ~isfield(EEG, 'data') || isempty(EEG.data)
        error('EEG data is empty or invalid.');
    end
    
    % Determine number of points to check (limit to 1000 points for efficiency)
    max_points = min(1000, EEG.pnts * EEG.trials);
    
    % Extract data for computation (channels x time)
    try
        data_subset = EEG.data(:, 1:max_points); % First 'max_points' samples
    catch
        error('Error accessing EEG data. Ensure EEG.data has the correct format.');
    end

    % Compute standard deviation for each channel
    channel_stds = std(data_subset, [], 2);  % Standard deviation across time
    
    % Handle edge cases (e.g., zero variance in channels)
    if any(isnan(channel_stds)) || any(channel_stds == 0)
        warning('Some channels have zero or NaN variance. Check your data for flatlines.');
    end
    
    % Sort standard deviations and remove extreme values (trim the first and last)
    sorted_stds = sort(channel_stds);
    if length(sorted_stds) > 2
        trimmed_stds = sorted_stds(2:end-1); % Trim one channel from both ends
    else
        trimmed_stds = sorted_stds; % Not enough data to trim
    end
    
    % Compute the mean of trimmed standard deviations
    mean_std = mean(trimmed_stds);
    
    % Derive quality index as a "spacing value"
    quality_index = mean_std * 3; % Multiplier to estimate spread
    
    % Round spacing for readability if value is large
    if quality_index > 10
        quality_index = round(quality_index);
    end
    
    % Print a brief message for the user
    fprintf('EEG Quality Index (Amplitude Spread Proxy): %.2f\n', quality_index);
    fprintf('Note: Larger values may indicate noisier or lower-quality data.\n');
end
