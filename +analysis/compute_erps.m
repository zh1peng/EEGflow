function ctx = compute_erps(ctx, args, ~)
    % Args: method (mean|median|trimmed), percent (numeric)
    if nargin < 2 || isempty(args), args = struct(); end
    if ~isfield(args, 'method'), args.method = 'mean'; end
    if ~isfield(args, 'percent'), args.percent = 5; end
    
    ctx_check(ctx);
    groups = fieldnames(ctx.Selection.Groups);
    if isempty(groups), error('No groups defined.'); end
    
    fprintf('Computing ERPs (%s)...\n', args.method);
    
    for g = 1:numel(groups)
        subs = ctx.Selection.Groups.(groups{g});
        for s = 1:numel(subs)
            sid = subs{s};
            for c = 1:numel(ctx.Selection.Conditions)
                cond = ctx.Selection.Conditions{c};
                data = ctx.Dataset.get_data(sid, cond);
                
                if ~isempty(data)
                    switch args.method
                        case 'mean', val = mean(data, 3);
                        case 'median', val = median(data, 3);
                        case 'trimmed', val = trimmean(data, args.percent, 3);
                    end
                    ctx.Results.ERPs.(sid).(cond) = val;
                end
            end
        end
    end
    fprintf('Done.\n');
end
