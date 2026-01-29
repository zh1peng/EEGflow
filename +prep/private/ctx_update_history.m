function context = ctx_update_history(context, op, params, status, metrics)
%CTX_UPDATE_HISTORY Append a standardized record to context.history
    rec = struct();
    rec.op = op;
    rec.params = params;
    rec.status = status;
    rec.metrics = metrics;
    rec.at = datestr(now, 31);

    if ~isfield(context, 'history') || isempty(context.history)
        context.history = rec;
        return;
    end

    allFields = union(fieldnames(context.history), fieldnames(rec));
    context.history = local_struct_reconcile(context.history, allFields);
    rec = local_struct_reconcile(rec, allFields);
    context.history(end+1) = rec;
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
