function field = state_subject_field(state, subject_id)
%STATE_SUBJECT_FIELD Resolve a subject field name in Dataset/Results.
%   Allows subject_id with or without "sub_" prefix.

    field = subject_id;
    if isfield(state.Dataset.data, field)
        return;
    end

    if startsWith(subject_id, 'sub_')
        stripped = subject_id(5:end);
        if isfield(state.Dataset.data, stripped)
            field = stripped;
        end
        return;
    end

    prefixed = ['sub_' subject_id];
    if isfield(state.Dataset.data, prefixed)
        field = prefixed;
    end
end
