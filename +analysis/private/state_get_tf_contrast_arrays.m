function info = state_get_tf_contrast_arrays(~, C)
%STATE_GET_TF_CONTRAST_ARRAYS Return subject-level arrays for TF contrast stats.
    info = struct();
    info.X1 = [];
    info.X2 = [];
    info.stat_design = '';
    info.contrast_design = '';
    info.metric = 'power';
    info.subjects1 = {};
    info.subjects2 = {};

    if isfield(C, 'metric') && ~isempty(C.metric)
        info.metric = C.metric;
    end
    if isfield(C, 'design') && ~isempty(C.design)
        info.contrast_design = C.design;
    end

    if isfield(C, 'maps')
        info.X1 = C.maps;
        info.X2 = [];
        info.stat_design = 'onesample';
        if isempty(info.contrast_design), info.contrast_design = 'within'; end
        if isfield(C, 'subjects'), info.subjects1 = C.subjects; end
        return;
    end

    if isfield(C, 'pos_maps') && isfield(C, 'neg_maps')
        info.X1 = C.pos_maps;
        info.X2 = C.neg_maps;
        if strcmpi(info.contrast_design, 'paired')
            info.stat_design = 'paired';
        else
            info.stat_design = 'two-sample';
        end
        if isempty(info.contrast_design), info.contrast_design = info.stat_design; end
        if isfield(C, 'subjects_pos'), info.subjects1 = C.subjects_pos; end
        if isfield(C, 'subjects_neg'), info.subjects2 = C.subjects_neg; end
        return;
    end

    error('TF contrast does not contain subject-level maps. Use tf_contrast_maps or tf_contrast_maps_between before statistics.');
end
