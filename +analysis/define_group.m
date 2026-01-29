function state = define_group(state, args, ~)
    % Args: name (char), subjects (cell)
    state_check(state);
    name = args.name;
    subs = args.subjects;

    miss = setdiff(subs, state.Dataset.subjects);
    if ~isempty(miss)
        warning('Missing subjects ignored: %s', strjoin(miss, ', '));
    end

    state.Selection.Groups.(name) = intersect(subs, state.Dataset.subjects);
    fprintf('Group %s defined (%d subs).\n', name, numel(state.Selection.Groups.(name)));
end
