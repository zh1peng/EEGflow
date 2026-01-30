function state = define_time_window(state, args, ~)
%DEFINE_TIME_WINDOW Define a named time window.
% Args: name (char), range (1x2 numeric)

    name = args.name;
    range = args.range;
    if numel(range) ~= 2 || range(1) >= range(2)
        error('Time window must be [start end] with start < end.');
    end
    state.Selection.TimeWindows.(name) = range;
    fprintf('Time window "%s": [%g %g] ms.\n', name, range(1), range(2));
end
