function ctx_check(ctx, req_field)
    if nargin < 2, req_field = ''; end
    if ~isfield(ctx, 'Dataset') || ~isa(ctx.Dataset, 'analysis.Dataset')
        error('erp_ctx:InvalidContext', 'Context must contain a valid analysis.Dataset.');
    end
    if ~isempty(req_field)
        if strcmp(req_field, 'ERPs') && (~isfield(ctx.Results, 'ERPs') || isempty(fieldnames(ctx.Results.ERPs)))
            error('erp_ctx:MissingResult', 'Subject ERPs not found. Run compute_erps first.');
        elseif strcmp(req_field, 'GA') && (~isfield(ctx.Results, 'GA') || isempty(fieldnames(ctx.Results.GA)))
            error('erp_ctx:MissingResult', 'Grand Averages not found. Run compute_ga first.');
        end
    end
end
