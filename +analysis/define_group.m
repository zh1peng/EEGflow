function state = define_group(state, args, ~)
    % Args: name (char), subjects (cell)
    state_check(state);
    if ~isfield(args, 'name') || isempty(args.name)
        error('Group name is required.');
    end
    if ~isfield(args, 'subjects') || isempty(args.subjects)
        error('Group subjects are required.');
    end

    name = char(args.name);
    subs = cellstr(args.subjects);
    subs = subs(:)';

    normalized = cell(size(subs));
    for i = 1:numel(subs)
        normalized{i} = state_subject_field(state, char(subs{i}));
    end

    present_mask = ismember(normalized, state.Dataset.subjects);
    miss = subs(~present_mask);
    keep = normalized(present_mask);
    keep = unique(keep, 'stable');

    if ~isempty(miss)
        warning('Missing subjects ignored: %s', strjoin(miss, ', '));
    end

    state.Selection.Groups.(name) = keep;
    fprintf('Group %s defined (%d subs).\n', name, numel(state.Selection.Groups.(name)));
end
