function state = state_update_history(state, op, params, status, metrics)
%STATE_UPDATE_HISTORY Append a standardized record to state.history.
    rec = struct();
    rec.op = op;
    rec.params = params;
    rec.status = status;
    rec.metrics = metrics;
    rec.at = datestr(now, 31);

    if ~isfield(state, 'history') || isempty(state.history)
        state.history = rec;
        return;
    end

    allFields = union(fieldnames(state.history), fieldnames(rec));
    state.history = local_struct_reconcile(state.history, allFields);
    rec = local_struct_reconcile(rec, allFields);
    state.history(end+1) = rec;
end

function s = local_struct_reconcile(s, fields)
    if isempty(s)
        s = struct();
    end
    for i = 1:numel(fields)
        f = fields{i};
        if ~isfield(s, f)
            for k = 1:numel(s)
                s(k).(f) = [];
            end
            if isempty(s)
                s.(f) = [];
            end
        end
    end
end
