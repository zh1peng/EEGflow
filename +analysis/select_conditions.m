function state = select_conditions(state, args, ~)
    % Args: conditions (cell)
    state_check(state);
    if ~isfield(args, 'conditions') || isempty(args.conditions)
        error('conditions is required.');
    end

    conds = cellstr(args.conditions);
    conds = conds(:)';
    ds_conds = state.Dataset.conditions(:)';

    cond_keys = lower(string(conds));
    ds_keys = lower(string(ds_conds));
    [tf, idx] = ismember(cond_keys, ds_keys);
    selected = ds_conds(idx(tf));
    selected = unique(selected, 'stable');
    miss = conds(~tf);

    if ~isempty(miss)
        warning('Missing conditions ignored: %s', strjoin(miss, ', '));
    end
    state.Selection.Conditions = selected;
    fprintf('Selected %d conditions.\n', numel(state.Selection.Conditions));
end
