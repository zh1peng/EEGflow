function state = erp_compute_erps(state, args, ~)
    % Args: method (mean|median|trimmed), percent (numeric)
    if nargin < 2 || isempty(args), args = struct(); end
    if ~isfield(args, 'method'), args.method = 'mean'; end
    if ~isfield(args, 'percent'), args.percent = 5; end

    state_check(state);
    groups = fieldnames(state.Selection.Groups);
    if isempty(groups), error('No groups defined.'); end
    if isempty(state.Selection.Conditions), error('No conditions selected.'); end

    state.Results.ERPs = struct();
    fprintf('Computing ERPs (%s)...\n', args.method);

    for g = 1:numel(groups)
        subs = state.Selection.Groups.(groups{g});
        for s = 1:numel(subs)
            sid = subs{s};
            sfield = state_subject_field(state, sid);
            for c = 1:numel(state.Selection.Conditions)
                cond = state.Selection.Conditions{c};
                data = state.Dataset.get_data(sfield, cond);

                if ~isempty(data)
                    switch lower(args.method)
                        case 'mean'
                            val = mean(data, 3);
                        case 'median'
                            val = median(data, 3);
                        case 'trimmed'
                            val = trimmean(data, args.percent, 3);
                        otherwise
                            error('Unsupported averaging method: %s', args.method);
                    end
                    if ~isfield(state.Results.ERPs, sfield)
                        state.Results.ERPs.(sfield) = struct();
                    end
                    state.Results.ERPs.(sfield).(cond) = val;
                end
            end
        end
    end
    fprintf('Done.\n');
end
