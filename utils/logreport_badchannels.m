function logreport_badchannels(BadChan, LogFile)
    % LOGREPORT_BADCHANNELS - Logs and summarizes bad channels detected by each module.
    %
    % Inputs:
    %   BadChan - Struct containing bad channels for each detection module.
    %   LogFile - Path to the log file for writing the report. If not found,
    %             prints to terminal instead.
    %
    % Outputs:
    %   None (writes to log file or terminal).
    
    % Try to open log file
    fid = fopen(LogFile, 'a');
    if fid == -1
        sprintf('[Warning] Unable to open log file: %s. Printing to terminal instead.', LogFile);
        fid = 1; % stdout (MATLAB command window)
    end

    % Print a header
    fprintf(fid, '================= Bad Channel Detection Report =================\n');
    fprintf(fid, 'Date: %s\n\n', datestr(now));
    
    % Define detection methods and their respective outputs
    methods = {
        'Kurtosis',               BadChan.Kurt;
        'Spectrum',               BadChan.Spec;
        'Probability',            BadChan.Prob;
        'FASTER Mean Correlation',BadChan.MeanCorr;
        'FASTER Variance',        BadChan.Variance;
        'FASTER Hurst Exponent',  BadChan.Hurst;
        'Flatline Detection',     BadChan.Flatline;
        'CleanRawData',           BadChan.CleanChan
    };

    % Iterate through each detection method and log results
    for i = 1:size(methods, 1)
        methodName  = methods{i, 1};
        badChannels = methods{i, 2};

        if ~isempty(badChannels)
            fprintf(fid, 'Bad Channels Identified by %s: %d\n', methodName, length(badChannels));
            fprintf(fid, 'Details: %s\n\n', mat2str(badChannels));
        else
            fprintf(fid, 'Bad Channels Identified by %s: None\n\n', methodName);
        end
    end

    % Log total unique bad channels
    if isfield(BadChan, 'all')
        fprintf(fid, 'Total Unique Bad Channels: %d\n', length(BadChan.all));
        fprintf(fid, 'Details: %s\n', mat2str(BadChan.all));
    else
        fprintf(fid, 'Total Unique Bad Channels: None\n');
    end

    fprintf(fid, '\n===============================================================\n\n');

    % Close only if actually writing to file
    if fid ~= 1
        fclose(fid);
    end
end
