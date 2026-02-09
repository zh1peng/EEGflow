function out = filter_complete_cases(state, args)
%FILTER_COMPLETE_CASES Filter subjects that have all required conditions.
%
% Args:
%   group (char)            group name in state.Selection.Groups
%   conditions (cellstr)    required conditions
%   return_only (logical)   default false (if true, return subject list)
%   update (logical)        default false (if true, updates state.Selection.Groups)
%
% Returns:
%   If return_only=true: cellstr of subjects
%   Else: updated state

    if nargin < 2, args = struct(); end
    if ~isfield(args, 'return_only'), args.return_only = false; end
    if ~isfield(args, 'update'), args.update = false; end

    state_check(state);
    g = args.group;
    conds = args.conditions;
    if ~isfield(state.Selection.Groups, g)
        error('Group "%s" not found.', g);
    end

    subs = state.Selection.Groups.(g);
    keep = true(1, numel(subs));
    for i = 1:numel(subs)
        sid = subs{i};
        sfield = state_subject_field(state, sid);
        ok = true;
        for c = 1:numel(conds)
            cond = conds{c};
            if ~isfield(state.Dataset.data, sfield) || ~isfield(state.Dataset.data.(sfield), cond)
                ok = false; break;
            end
            if isempty(state.Dataset.data.(sfield).(cond))
                ok = false; break;
            end
        end
        keep(i) = ok;
    end
    subs_out = subs(keep);

    if args.return_only
        out = subs_out;
    else
        if args.update
            state.Selection.Groups.(g) = subs_out;
        end
        out = state;
    end
end
