function state = tfr_define_contrast(state, args, ~)
    % Args: name, pos_term {Group, Cond}, neg_term {Group, Cond}
    name = args.name;
    pos = args.pos_term;
    neg = args.neg_term;

    state_check(state, 'GA_TFD');

    try
        P = state.Results.GA_TFD.(pos{1}).(pos{2});
        N = state.Results.GA_TFD.(neg{1}).(neg{2});
    catch
        error('GA_TFD data missing for terms provided.');
    end

    state.Results.Contrasts.(name).tfd = P.tfd - N.tfd;
    state.Results.Contrasts.(name).positive_term = pos;
    state.Results.Contrasts.(name).negative_term = neg;
    state.Results.Contrasts.(name).n_pos = P.n;
    state.Results.Contrasts.(name).n_neg = N.n;

    fprintf('Contrast "%s" defined.\n', name);
end
