function reg = init_registry()
%INIT_REGISTRY Build a prep-only registry (op -> function_handle).

    reg = containers.Map('KeyType', 'char', 'ValueType', 'any');

    % I/O
    reg('load_set') = @prep.load_set;
    reg('load_mff') = @prep.load_mff;
    reg('save_set') = @prep.save_set;

    % Preprocessing
    reg('select_channels') = @prep.select_channels;
    reg('remove_channels') = @prep.remove_channels;
    reg('downsample') = @prep.downsample;
    reg('filter') = @prep.filter;
    reg('remove_powerline') = @prep.remove_powerline;
    reg('crop_by_markers') = @prep.crop_by_markers;
    reg('insert_relative_markers') = @prep.insert_relative_markers;
    reg('correct_baseline') = @prep.correct_baseline;
    reg('remove_bad_channels') = @prep.remove_bad_channels;
    reg('interpolate') = @prep.interpolate;
    reg('interpolate_bad_channels_epoch') = @prep.interpolate_bad_channels_epoch;
    reg('reref') = @prep.reref;
    reg('remove_bad_epoch') = @prep.remove_bad_epoch;
    reg('remove_bad_ICs') = @prep.remove_bad_ICs;
    reg('segment_task') = @prep.segment_task;
    reg('segment_rest') = @prep.segment_rest;
    reg('edit_chantype') = @prep.edit_chantype;
end
