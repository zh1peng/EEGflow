function [stack, n] = state_collect_metric_tfr(state, subject_ids, condition_name, metric)
%STATE_COLLECT_METRIC_TFR Collect TFR metrics into [chan x f x t x subj].
    stack = [];
    n = 0;

    use_tf = isfield(state, 'Results') && isfield(state.Results, 'TF') && ~isempty(fieldnames(state.Results.TF));

    for i = 1:numel(subject_ids)
        sid = subject_ids{i};
        sfield = state_subject_field(state, sid);

        if use_tf && isfield(state.Results.TF, sfield) && isfield(state.Results.TF.(sfield), condition_name)
            S = state.Results.TF.(sfield).(condition_name);
        elseif isfield(state.Dataset.data, sfield) && isfield(state.Dataset.data.(sfield), condition_name)
            S = state.Dataset.data.(sfield).(condition_name);
        else
            continue;
        end

        if isfield(S, metric)
            A = S.(metric);
        elseif strcmpi(metric, 'power') && isfield(S, 'ersp')
            A = S.ersp;
        else
            continue;
        end

        if ndims(A) == 4
            A = mean(A, 4);
        end

        if isempty(stack)
            stack = zeros([size(A) numel(subject_ids)]);
        end
        n = n + 1;
        stack(:, :, :, n) = A;
    end

    if n == 0
        stack = [];
    elseif n < size(stack, 4)
        stack = stack(:, :, :, 1:n);
    end
end
