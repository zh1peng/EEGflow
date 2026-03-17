function state = define_time_window(state, args, ~)
%DEFINE_TIME_WINDOW Define a named time window.
% Args: name (char), range (1x2 numeric)

    state_check(state);
    if ~isfield(args, 'name') || isempty(args.name)
        error('Time window name is required.');
    end
    if ~isfield(args, 'range') || isempty(args.range)
        error('Time window range is required.');
    end

    name = char(args.name);
    range = args.range;
    if numel(range) ~= 2 || range(1) >= range(2) || any(~isfinite(range))
        error('Time window must be [start end] with start < end.');
    end
    ds_t = state.Dataset.times;
    if range(2) < ds_t(1) || range(1) > ds_t(end) || ~any(ds_t >= range(1) & ds_t <= range(2))
        error('Time window [%g %g] ms does not overlap dataset time range [%g %g] ms.', ...
            range(1), range(2), ds_t(1), ds_t(end));
    end
    state.Selection.TimeWindows.(name) = range;
    fprintf('Time window "%s": [%g %g] ms.\n', name, range(1), range(2));
end
