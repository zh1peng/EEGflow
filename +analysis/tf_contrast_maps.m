function state = tf_contrast_maps(state, args, ~)
%TF_CONTRAST_MAPS Build subject-level within-group TF contrast maps.
%
% Args:
%   name (char)              contrast name
%   pos_term {group, cond}   positive term
%   neg_term {group, cond}   negative term
%   metric (char)            default 'power'
%   require_complete (bool)  default true (subjects must have both conditions)

    if nargin < 2, args = struct(); end
    if ~isfield(args, 'metric'), args.metric = 'power'; end
    if ~isfield(args, 'require_complete'), args.require_complete = true; end

    state_check(state);
    name = args.name;
    pos = args.pos_term;
    neg = args.neg_term;

    if ~iscell(pos) || ~iscell(neg) || numel(pos) < 2 || numel(neg) < 2
        error('pos_term/neg_term must be {group, condition}.');
    end
    if ~strcmp(pos{1}, neg{1})
        error('tf_contrast_maps is within-group only. Use tf_contrast_maps_between for between-group.');
    end

    group = pos{1};
    condP = pos{2};
    condN = neg{2};

    if ~isfield(state.Selection.Groups, group)
        error('Group "%s" not found.', group);
    end
    subs = state.Selection.Groups.(group);
    if args.require_complete
        subs = analysis.filter_complete_cases(state, struct('group', group, 'conditions', {{condP, condN}}, 'return_only', true));
    end

    [Xp, ~] = state_collect_metric_tf(state, subs, condP, args.metric);
    [Xn, ~] = state_collect_metric_tf(state, subs, condN, args.metric);
    if isempty(Xp) || isempty(Xn)
        error('No data found for contrast terms.');
    end
    if size(Xp, 4) ~= size(Xn, 4)
        error('Subject count mismatch for paired contrast.');
    end

    maps = Xp - Xn; % [chan x f x t x subj]

    [freqs, times] = resolve_tf_axes(state, subs, condP);

    state.Results.Contrasts.(name).maps = maps;
    state.Results.Contrasts.(name).tfd = mean(maps, 4);
    state.Results.Contrasts.(name).positive_term = pos;
    state.Results.Contrasts.(name).negative_term = neg;
    state.Results.Contrasts.(name).subjects = subs;
    state.Results.Contrasts.(name).metric = args.metric;
    state.Results.Contrasts.(name).design = 'within';
    state.Results.Contrasts.(name).freqs = freqs;
    state.Results.Contrasts.(name).times = times;

    fprintf('Subject-level contrast "%s" built (%s: %s-%s).\n', name, group, condP, condN);
end

function [freqs, times] = resolve_tf_axes(state, subjects, condition)
    freqs = [];
    times = [];
    if isfield(state.Dataset.data, 'meta')
        meta = state.Dataset.data.meta;
        if isfield(meta, 'freqs'), freqs = meta.freqs; end
        if isfield(meta, 'times'), times = meta.times; end
    end
    if ~isempty(freqs) && ~isempty(times)
        return;
    end
    if isfield(state.Results, 'TF')
        for i = 1:numel(subjects)
            sfield = state_subject_field(state, subjects{i});
            if isfield(state.Results.TF, sfield) && isfield(state.Results.TF.(sfield), condition)
                entry = state.Results.TF.(sfield).(condition);
                if isfield(entry, 'freqs'), freqs = entry.freqs; end
                if isfield(entry, 'times'), times = entry.times; end
                break;
            end
        end
    end
    if isempty(freqs) || isempty(times)
        error('TF axes (freqs/times) not found in Dataset.meta or Results.TF.');
    end
end
