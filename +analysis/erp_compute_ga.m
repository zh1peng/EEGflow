function state = erp_compute_ga(state, ~, ~)
    state_check(state, 'ERPs');
    groups = fieldnames(state.Selection.Groups);
    if isempty(groups), error('No groups defined.'); end
    if isempty(state.Selection.Conditions), error('No conditions selected.'); end

    state.Results.GA = struct();
    fprintf('Computing GA...\n');

    for g = 1:numel(groups)
        gn = groups{g};
        subs = state.Selection.Groups.(gn);
        for c = 1:numel(state.Selection.Conditions)
            cn = state.Selection.Conditions{c};
            [stack, ~] = state_collect_erps(state, subs, cn);
            if ~isempty(stack)
                state.Results.GA.(gn).(cn).erp = mean(stack, 3);
                state.Results.GA.(gn).(cn).n = size(stack, 3);
            else
                warning('No subject ERPs found for %s:%s', gn, cn);
            end
        end
    end
    fprintf('Done.\n');
end
