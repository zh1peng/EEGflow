function register_prep(reg)
    % I/O Operations
    register_op(reg, 'load_set',            @prep.load_set);
    register_op(reg, 'load_mff',            @prep.load_mff);
    register_op(reg, 'save_set',            @prep.save_set);

    % Preprocessing Operations
    register_op(reg, 'select_channels',     @prep.select_channels);
    register_op(reg, 'remove_channels',     @prep.remove_channels);
    register_op(reg, 'downsample',          @prep.downsample);
    register_op(reg, 'filter',              @prep.filter);
    register_op(reg, 'remove_powerline',    @prep.remove_powerline);
    register_op(reg, 'crop_by_markers',     @prep.crop_by_markers);
    register_op(reg, 'insert_relative_markers', @prep.insert_relative_markers);
    register_op(reg, 'correct_baseline',    @prep.correct_baseline);
    register_op(reg, 'remove_bad_channels', @prep.remove_bad_channels);
    register_op(reg, 'interpolate',         @prep.interpolate);
    register_op(reg, 'interpolate_bad_channels_epoch', @prep.interpolate_bad_channels_epoch);
    register_op(reg, 'reref',               @prep.reref);
    register_op(reg, 'remove_bad_epoch',    @prep.remove_bad_epoch);
    register_op(reg, 'remove_bad_ICs',      @prep.remove_bad_ICs);
    register_op(reg, 'segment_task',        @prep.segment_task);
    register_op(reg, 'segment_rest',        @prep.segment_rest);
end
