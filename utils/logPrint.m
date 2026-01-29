function logPrint(LogFile, msg)
    % logPrint - Print a message to both log file and MATLAB console (robust).
    %
    % Usage:
    %   logPrint(LogFile, msg)
    %
    % If the log file cannot be opened, message will still be printed
    % to MATLAB Command Window without error.

    % Try open log file in append mode
    logFID = fopen(LogFile, 'a');
    
    % Always print to Command Window
    fprintf('%s\n', msg);

    % If file opened successfully, also write to it
    if logFID ~= -1
        fprintf(logFID, '%s\n', msg);
        fclose(logFID);
    else
        % Optional: warn once that logging failed
        sprintf('[Warning] Could not open log file: %s. Only printed to console.', LogFile);
    end
end

