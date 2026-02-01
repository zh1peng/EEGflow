function logplot_badchannels(EEG, badChannels, logPath, detectionType)
% LOGPLOT_CHANNEL - Save and log properties of detected bad channels.
%
% Inputs:
%   EEG            - EEGLAB EEG structure.
%   badChannels    - Array of bad channel indices.
%   logPath        - Path to save channel property figures.
%   detectionType  - String indicating the detection method (e.g., 'Spec', 'Kurt').
%
% Outputs:
%   None. Saves figures to the specified logPath, or displays them if logPath is invalid.

close all
    % Check if logPath is valid for saving
    can_save_plot = false;
    if ischar(logPath) && ~isempty(logPath) && exist(logPath, 'dir')
        can_save_plot = true;
    end

    if ~can_save_plot
        fprintf('[logplot_badchannels] Warning: Invalid or non-existent LogPath ("%s"). Plots will be displayed but NOT saved.\n', logPath);
    end

    % Loop through detected bad channels
    if ~isempty(badChannels)
        for i = 1:length(badChannels)
            chanIdx = badChannels(i);
            % Plot channel properties using pop_prop
            pop_prop(EEG, 1, chanIdx, NaN, {'freqrange', [2 40]});

            if can_save_plot
                % Save the figure with detection method and channel index
                saveas(gcf, fullfile(logPath, sprintf('BadChannel_%s_%d_Properties.png', detectionType, chanIdx)));
                % Close the figure to avoid clutter
                close(gcf);
            else
                % If cannot save, just display the plot. User will need to close it.
                fprintf('[logplot_badchannels] Displaying plot for bad channel %d (Type: %s). Please close the figure manually.\n', chanIdx, detectionType);
            end
        end
    end
end
