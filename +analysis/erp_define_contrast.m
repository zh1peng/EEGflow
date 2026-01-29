function state = erp_define_contrast(state, args, ~)
%ERP_DEFINE_CONTRAST Define an ERP contrast from GA terms.
% Args: name, pos_term {Group, Cond}, neg_term {Group, Cond}

    state_check(state, 'GA');
    name = args.name;
    pos = args.pos_term;
    neg = args.neg_term;

    [pos_erp, pos_n] = get_ga_term(state, pos);
    [neg_erp, neg_n] = get_ga_term(state, neg);
    diff_wave = pos_erp - neg_erp;

    state.Results.Contrasts.(name).erp = diff_wave;
    state.Results.Contrasts.(name).positive_term = pos;
    state.Results.Contrasts.(name).negative_term = neg;
    state.Results.Contrasts.(name).n_positive = pos_n;
    state.Results.Contrasts.(name).n_negative = neg_n;
    fprintf('Contrast "%s" computed.\n', name);
end

function [erp, n] = get_ga_term(state, term)
    if numel(term) ~= 2
        error('Term must be {GroupName, ConditionName}.');
    end
    group_name = term{1};
    cond_name = term{2};
    if ~isfield(state.Results.GA, group_name) || ~isfield(state.Results.GA.(group_name), cond_name)
        error('GA term not found for %s:%s.', group_name, cond_name);
    end
    erp = state.Results.GA.(group_name).(cond_name).erp;
    n = state.Results.GA.(group_name).(cond_name).n;
end
