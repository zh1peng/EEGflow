function state = log_step(state, meta, logFile, msg)
%LOG_STEP Emit a log via both logPrint (file/console) and state_log (pipeline).
%
% Usage:
%   state = log_step(state, meta, logFile, msg);
%
% This keeps state untouched except for optional runtime logging if meta.logger is set.

    if nargin < 4
        return;
    end

    if nargin >= 3
        logPrint(logFile, msg);
    end

    state_log(meta, msg);
end
