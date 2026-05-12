function [freqs, times] = state_get_tf_axes(state, subjects, condition, contrast)
%STATE_GET_TF_AXES Resolve TF frequency/time axes from contrast, dataset, or Results.TF.
    if nargin < 2, subjects = {}; end
    if nargin < 3, condition = ''; end
    if nargin < 4, contrast = struct(); end

    freqs = [];
    times = [];

    if isstruct(contrast)
        if isfield(contrast, 'freqs'), freqs = contrast.freqs; end
        if isfield(contrast, 'times'), times = contrast.times; end
    end
    if ~isempty(freqs) && ~isempty(times)
        return;
    end

    if isfield(state, 'Dataset') && isfield(state.Dataset.data, 'meta')
        meta = state.Dataset.data.meta;
        if isempty(freqs) && isfield(meta, 'freqs'), freqs = meta.freqs; end
        if isempty(times) && isfield(meta, 'times'), times = meta.times; end
    end
    if ~isempty(freqs) && ~isempty(times)
        return;
    end

    if ischar(subjects) || isstring(subjects)
        subjects = cellstr(subjects);
    end
    if isstring(condition), condition = char(condition); end

    if isfield(state, 'Results') && isfield(state.Results, 'TF')
        for i = 1:numel(subjects)
            sfield = state_subject_field(state, subjects{i});
            if isfield(state.Results.TF, sfield) && isfield(state.Results.TF.(sfield), condition)
                entry = state.Results.TF.(sfield).(condition);
                if isempty(freqs) && isfield(entry, 'freqs'), freqs = entry.freqs; end
                if isempty(times) && isfield(entry, 'times'), times = entry.times; end
                if ~isempty(freqs) && ~isempty(times), return; end
            end
        end
    end

    error('TF axes (freqs/times) not found in contrast, Dataset.meta, or Results.TF.');
end
