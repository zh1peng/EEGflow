function ctx_log(meta, msg)
%CTX_LOG Log using meta.logger if provided
    if isfield(meta, 'logger') && ~isempty(meta.logger)
        meta.logger(msg);
    else
        fprintf('%s\n', msg);
    end
end
