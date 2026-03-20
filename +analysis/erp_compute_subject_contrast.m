function state = erp_compute_subject_contrast(state, args, ~)
%ERP_COMPUTE_SUBJECT_CONTRAST Build within-group subject-level ERP difference waves.
% Args:
%   name (char)
%   pos_term {group, condition}
%   neg_term {group, condition}

    if nargin < 2, args = struct(); end
    if ~isfield(args, 'name') || isempty(args.name)
        error('name is required.');
    end
    if ~isfield(args, 'pos_term') || ~isfield(args, 'neg_term')
        error('pos_term and neg_term are required.');
    end

    state_check(state, 'ERPs');
    name = char(args.name);
    if isfield(state.Results, 'SubjectContrasts') && isfield(state.Results.SubjectContrasts, name)
        error('Subject contrast "%s" already exists.', name);
    end
    pos = args.pos_term;
    neg = args.neg_term;

    if ~iscell(pos) || ~iscell(neg) || numel(pos) ~= 2 || numel(neg) ~= 2
        error('pos_term and neg_term must be {group, condition}.');
    end
    if ~strcmp(pos{1}, neg{1})
        error('Subject contrast is within-group only. pos_term and neg_term must use the same group.');
    end

    group_name = pos{1};
    cond_pos = pos{2};
    cond_neg = neg{2};
    if ~isfield(state.Selection.Groups, group_name)
        error('Group "%s" not found.', group_name);
    end

    subjects = state.Selection.Groups.(group_name);
    if isempty(subjects)
        error('Group "%s" has no subjects.', group_name);
    end

    missing_msgs = {};
    stack_cell = cell(1, numel(subjects));
    for i = 1:numel(subjects)
        sid = subjects{i};
        sfield = state_subject_field(state, sid);
        if ~isfield(state.Results.ERPs, sfield)
            missing_msgs{end+1} = sprintf('%s (no ERP entry)', sid); %#ok<AGROW>
            continue;
        end
        if ~isfield(state.Results.ERPs.(sfield), cond_pos)
            missing_msgs{end+1} = sprintf('%s (missing %s)', sid, cond_pos); %#ok<AGROW>
            continue;
        end
        if ~isfield(state.Results.ERPs.(sfield), cond_neg)
            missing_msgs{end+1} = sprintf('%s (missing %s)', sid, cond_neg); %#ok<AGROW>
            continue;
        end

        pos_erp = state.Results.ERPs.(sfield).(cond_pos);
        neg_erp = state.Results.ERPs.(sfield).(cond_neg);
        if ~isequal(size(pos_erp), size(neg_erp))
            error('Size mismatch for subject %s: %s is [%d %d], %s is [%d %d].', ...
                sid, cond_pos, size(pos_erp, 1), size(pos_erp, 2), cond_neg, size(neg_erp, 1), size(neg_erp, 2));
        end
        stack_cell{i} = pos_erp - neg_erp;
    end

    if ~isempty(missing_msgs)
        error('Subject contrast "%s" failed due to missing required conditions: %s', ...
            name, strjoin(missing_msgs, '; '));
    end

    erps = cat(3, stack_cell{:}); % [chan x time x subj]
    ga = mean(erps, 3);

    state.Results.SubjectContrasts.(name).erps = erps;
    state.Results.SubjectContrasts.(name).ga = ga;
    state.Results.SubjectContrasts.(name).subjects = subjects;
    state.Results.SubjectContrasts.(name).n = numel(subjects);
    state.Results.SubjectContrasts.(name).definition = struct( ...
        'design', 'within', ...
        'group', group_name, ...
        'positive_term', pos, ...
        'negative_term', neg);

    fprintf('Subject contrast "%s" computed (%s: %s-%s, N=%d). [EEGflow v%s]\n', ...
        name, group_name, cond_pos, cond_neg, numel(subjects), analysis.get_version());
end
