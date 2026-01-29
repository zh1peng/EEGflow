function state = tfr_define_band(state, args, ~)
    % Args: name (char), range (1x2 double)
    if args.range(1) >= args.range(2)
        error('Range must be [low high]');
    end
    state.Selection.FreqBands.(args.name) = args.range;
    fprintf('Band "%s": [%g %g] Hz\n', args.name, args.range(1), args.range(2));
end
