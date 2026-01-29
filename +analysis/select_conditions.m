function state = select_conditions(state, args, ~)
    % Args: conditions (cell)
    state_check(state);
    conds = args.conditions;
    miss = setdiff(conds, state.Dataset.conditions);
    if ~isempty(miss)
        warning('Missing conditions ignored: %s', strjoin(miss, ', '));
    end
    state.Selection.Conditions = intersect(conds, state.Dataset.conditions);
    fprintf('Selected %d conditions.\n', numel(state.Selection.Conditions));
end
