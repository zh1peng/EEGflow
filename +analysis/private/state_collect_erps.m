function [stack, found] = state_collect_erps(state, subjects, condition)
%STATE_COLLECT_ERPS Collect subject ERPs into [chan x time x subj].
    stack_cell = {};
    found = {};
    for i = 1:numel(subjects)
        sid = subjects{i};
        sfield = state_subject_field(state, sid);
        if isfield(state.Results.ERPs, sfield) && isfield(state.Results.ERPs.(sfield), condition)
            stack_cell{end+1} = state.Results.ERPs.(sfield).(condition); %#ok<AGROW>
            found{end+1} = sid; %#ok<AGROW>
        end
    end
    if ~isempty(stack_cell)
        stack = cat(3, stack_cell{:});
    else
        stack = [];
    end
end
