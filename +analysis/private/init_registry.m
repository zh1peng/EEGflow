function reg = init_registry()
%INIT_REGISTRY Build an analysis-only registry (op -> function_handle).

    reg = containers.Map('KeyType', 'char', 'ValueType', 'any');

    % Common selection/definition
    reg('define_group') = @analysis.define_group;
    reg('select_conditions') = @analysis.select_conditions;
    reg('define_roi') = @analysis.define_roi;
    reg('define_time_window') = @analysis.define_time_window;

    % ERP
    reg('erp_compute_erps') = @analysis.erp_compute_erps;
    reg('erp_compute_ga') = @analysis.erp_compute_ga;
    reg('erp_define_contrast') = @analysis.erp_define_contrast;
    reg('erp_compute_stats') = @analysis.erp_compute_stats;
    reg('erp_plot_erp') = @analysis.erp_plot_erp;
    reg('erp_plot_contrast') = @analysis.erp_plot_contrast;
    reg('erp_plot_topo') = @analysis.erp_plot_topo;
    reg('erp_extract_feature') = @analysis.erp_extract_feature;
    reg('erp_compute_subject_contrast') = @analysis.erp_compute_subject_contrast;
    reg('erp_compute_subject_contrast_stats') = @analysis.erp_compute_subject_contrast_stats;
    reg('erp_plot_subject_contrast') = @analysis.erp_plot_subject_contrast;
    reg('erp_extract_subject_contrast_feature') = @analysis.erp_extract_subject_contrast_feature;

    % TF
    reg('tf_transform') = @analysis.tf_transform;
    reg('tf_cache_save') = @analysis.tf_cache_save;
    reg('tf_cache_load') = @analysis.tf_cache_load;
    reg('tf_cache_is_compatible') = @analysis.tf_cache_is_compatible;
    reg('tf_compute') = @analysis.tf_compute;
    reg('tf_compute_ga') = @analysis.tf_compute_ga;
    reg('tf_define_band') = @analysis.tf_define_band;
    reg('tf_define_contrast') = @analysis.tf_define_contrast;
    reg('tf_band_stats') = @analysis.tf_band_stats;
    reg('tf_plot') = @analysis.tf_plot;
    reg('tf_plot_band_timecourse') = @analysis.tf_plot_band_timecourse;
    reg('tf_plot_contrast') = @analysis.tf_plot_contrast;
    reg('tf_plot_topo') = @analysis.tf_plot_topo;
    reg('tf_extract_features') = @analysis.tf_extract_features;
    reg('tf_contrast_maps') = @analysis.tf_contrast_maps;
    reg('tf_contrast_maps_between') = @analysis.tf_contrast_maps_between;
    reg('tf_stats_plane') = @analysis.tf_stats_plane;
    reg('tf_feature_stats') = @analysis.tf_feature_stats;
    reg('filter_complete_cases') = @analysis.filter_complete_cases;
end
