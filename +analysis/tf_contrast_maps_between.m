function state = tf_contrast_maps_between(state, args, ~)
%TF_CONTRAST_MAPS_BETWEEN Build subject-level between-group TF contrast maps.
%
% Args:
%   name (char)
%   pos_term {group, cond}  positive term (group, condition)
%   neg_term {group, cond}  negative term (group, condition)
%   metric (char)           default 'power'
%   pos_within {condA, condB} optional (for diff-in-diff on pos group)
%   neg_within {condA, condB} optional (for diff-in-diff on neg group)

    if nargin < 2, args = struct(); end
    if ~isfield(args, 'metric'), args.metric = 'power'; end

    state_check(state);
    name = args.name;
    pos = args.pos_term;
    neg = args.neg_term;

    if ~iscell(pos) || ~iscell(neg) || numel(pos) < 2 || numel(neg) < 2
        error('pos_term/neg_term must be {group, condition}.');
    end

    gpos = pos{1};
    gneg = neg{1};

    if ~isfield(state.Selection.Groups, gpos) || ~isfield(state.Selection.Groups, gneg)
        error('Group(s) not found.');
    end

    subs_pos = state.Selection.Groups.(gpos);
    subs_neg = state.Selection.Groups.(gneg);

    % Build maps for pos group
    if isfield(args, 'pos_within') && ~isempty(args.pos_within)
        condA = args.pos_within{1};
        condB = args.pos_within{2};
        [Xa, ~] = state_collect_metric_tf(state, subs_pos, condA, args.metric);
        [Xb, ~] = state_collect_metric_tf(state, subs_pos, condB, args.metric);
        maps_pos = Xa - Xb;
        pos_desc = sprintf('%s-%s', condA, condB);
    else
        condP = pos{2};
        [maps_pos, ~] = state_collect_metric_tf(state, subs_pos, condP, args.metric);
        pos_desc = condP;
    end

    % Build maps for neg group
    if isfield(args, 'neg_within') && ~isempty(args.neg_within)
        condA = args.neg_within{1};
        condB = args.neg_within{2};
        [Xa, ~] = state_collect_metric_tf(state, subs_neg, condA, args.metric);
        [Xb, ~] = state_collect_metric_tf(state, subs_neg, condB, args.metric);
        maps_neg = Xa - Xb;
        neg_desc = sprintf('%s-%s', condA, condB);
    else
        condN = neg{2};
        [maps_neg, ~] = state_collect_metric_tf(state, subs_neg, condN, args.metric);
        neg_desc = condN;
    end

    if isempty(maps_pos) || isempty(maps_neg)
        error('No data found for contrast terms.');
    end

    [freqs, times] = state_get_tf_axes(state, subs_pos, pos{2});

    state.Results.Contrasts.(name).pos_maps = maps_pos;
    state.Results.Contrasts.(name).neg_maps = maps_neg;
    state.Results.Contrasts.(name).tfd = mean(maps_pos, 4) - mean(maps_neg, 4);
    state.Results.Contrasts.(name).positive_term = pos;
    state.Results.Contrasts.(name).negative_term = neg;
    state.Results.Contrasts.(name).subjects_pos = subs_pos;
    state.Results.Contrasts.(name).subjects_neg = subs_neg;
    state.Results.Contrasts.(name).metric = args.metric;
    state.Results.Contrasts.(name).design = 'between';
    if isfield(args, 'pos_within') || isfield(args, 'neg_within')
        state.Results.Contrasts.(name).design = 'diff_in_diff';
        state.Results.Contrasts.(name).pos_within = args.pos_within;
        state.Results.Contrasts.(name).neg_within = args.neg_within;
    end
    state.Results.Contrasts.(name).freqs = freqs;
    state.Results.Contrasts.(name).times = times;
    state.Results.Contrasts.(name).desc = sprintf('%s(%s) - %s(%s)', gpos, pos_desc, gneg, neg_desc);

    fprintf('Between-group contrast "%s" built: %s.\n', name, state.Results.Contrasts.(name).desc);
end
