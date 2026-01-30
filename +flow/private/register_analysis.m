function register_analysis(reg)
    register_op(reg, 'define_group',      @analysis.define_group);
    register_op(reg, 'select_conditions', @analysis.select_conditions);
    register_op(reg, 'define_roi',        @analysis.define_roi);
    register_op(reg, 'define_time_window',@analysis.define_time_window);

    register_op(reg, 'erp_compute_erps',       @analysis.erp_compute_erps);
    register_op(reg, 'erp_compute_ga',         @analysis.erp_compute_ga);
    register_op(reg, 'erp_define_contrast',    @analysis.erp_define_contrast);
    register_op(reg, 'erp_compute_stats',      @analysis.erp_compute_stats);
    register_op(reg, 'erp_plot_erp',           @analysis.erp_plot_erp);
    register_op(reg, 'erp_plot_contrast',      @analysis.erp_plot_contrast);
    register_op(reg, 'erp_plot_topo',          @analysis.erp_plot_topo);
    register_op(reg, 'erp_extract_feature',    @analysis.erp_extract_feature);

    register_op(reg, 'tf_init',            @analysis.tf_init);
    register_op(reg, 'tf_compute',         @analysis.tf_compute);
    register_op(reg, 'tf_compute_ga',      @analysis.tf_compute_ga);
    register_op(reg, 'tf_define_band',     @analysis.tf_define_band);
    register_op(reg, 'tf_define_contrast', @analysis.tf_define_contrast);
    register_op(reg, 'tf_band_stats',      @analysis.tf_band_stats);
    register_op(reg, 'tf_plot',            @analysis.tf_plot);
    register_op(reg, 'tf_extract_features',@analysis.tf_extract_features);
end
