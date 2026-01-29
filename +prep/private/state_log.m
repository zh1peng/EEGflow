function state_log(meta, msg)
%STATE_LOG Log using meta.logger if provided, else fprintf.
    if nargin < 2
        return;
    end
    if nargin >= 1 && isstruct(meta) && isfield(meta, 'logger') && ~isempty(meta.logger)
        meta.logger(msg);
    else
        fprintf('%s\n', msg);
    end
end
