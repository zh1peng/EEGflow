function [state, S] = tf_feature_stats(state, args, ~)
%TF_FEATURE_STATS Summarize TF feature tables and run group comparisons.
%
% Args:
%   table (table)        input table (default: state.Results.Features.LastTable)
%   metric (char)        column name to compare (default: 'Mean')
%   group_field (char)   default: 'Group'
%   condition_field      default: 'Condition'
%   compare_groups       cell {g1,g2} (optional)
%   method               'ttest2' (default) | 'ranksum'
%
% Returns:
%   S.summary (table) and S.compare (struct)

    if nargin < 2, args = struct(); end
    if ~isfield(args, 'metric'), args.metric = 'Mean'; end
    if ~isfield(args, 'group_field'), args.group_field = 'Group'; end
    if ~isfield(args, 'condition_field'), args.condition_field = 'Condition'; end
    if ~isfield(args, 'method'), args.method = 'ttest2'; end

    if isfield(args, 'table') && ~isempty(args.table)
        T = args.table;
    elseif isfield(state.Results, 'Features') && isfield(state.Results.Features, 'LastTable')
        T = state.Results.Features.LastTable;
    else
        error('No feature table provided.');
    end

    if ~istable(T) || ~ismember(args.metric, T.Properties.VariableNames)
        error('Metric "%s" not found in table.', args.metric);
    end

    groups = unique(T.(args.group_field));
    conds = unique(T.(args.condition_field));
    rows = {};
    for g = 1:numel(groups)
        for c = 1:numel(conds)
            mask = strcmp(T.(args.group_field), groups{g}) & strcmp(T.(args.condition_field), conds{c});
            v = T.(args.metric)(mask);
            if isempty(v), continue; end
            rows(end+1,:) = {groups{g}, conds{c}, numel(v), mean(v), std(v), std(v)/sqrt(numel(v))}; %#ok<AGROW>
        end
    end
    summary = cell2table(rows, 'VariableNames', {'Group','Condition','N','Mean','SD','SEM'});

    S = struct();
    S.summary = summary;
    S.compare = struct();

    if isfield(args, 'compare_groups') && numel(args.compare_groups) == 2
        g1 = args.compare_groups{1};
        g2 = args.compare_groups{2};
        for c = 1:numel(conds)
            mask1 = strcmp(T.(args.group_field), g1) & strcmp(T.(args.condition_field), conds{c});
            mask2 = strcmp(T.(args.group_field), g2) & strcmp(T.(args.condition_field), conds{c});
            x1 = T.(args.metric)(mask1);
            x2 = T.(args.metric)(mask2);
            if isempty(x1) || isempty(x2), continue; end

            switch lower(args.method)
                case 'ranksum'
                    p = ranksum(x1, x2);
                    t = NaN;
                otherwise
                    [~, p, ~, stats] = ttest2(x1, x2);
                    t = stats.tstat;
            end
            d = compute_cohens_d(x1, x2);
            S.compare.(conds{c}) = struct('group1', g1, 'group2', g2, ...
                'n1', numel(x1), 'n2', numel(x2), 't', t, 'p', p, 'd', d);
        end
    end

    state.Results.Features.Stats = S;
end

function d = compute_cohens_d(x1, x2)
    s_pool = sqrt(((numel(x1)-1)*var(x1) + (numel(x2)-1)*var(x2)) / (numel(x1)+numel(x2)-2));
    d = (mean(x1) - mean(x2)) / s_pool;
end
