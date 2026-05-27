function logPrint(LogFile, msg)
%LOGPRINT Print a message to both log file and MATLAB console (robust).
%
% Usage:
%   logPrint(LogFile, msg)
%
% If the log file cannot be opened, the message is still printed to the console.

    if nargin < 2
        return;
    end

    fprintf('%s\n', msg);

    if nargin < 1 || isempty(LogFile)
        return;
    end

    fid = fopen(LogFile, 'a');
    if fid ~= -1
        fprintf(fid, '%s\n', msg);
        fclose(fid);
    end
end

