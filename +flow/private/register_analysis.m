function register_analysis(reg)
    register_op(reg, 'define_group',      @analysis.define_group);
    register_op(reg, 'select_conditions', @analysis.select_conditions);

    register_op(reg, 'erp_define_group',       @analysis.erp_define_group);
    register_op(reg, 'erp_select_conditions',  @analysis.erp_select_conditions);
    register_op(reg, 'erp_define_roi',         @analysis.erp_define_roi);
    register_op(reg, 'erp_define_time_window', @analysis.erp_define_time_window);
    register_op(reg, 'erp_compute_erps',       @analysis.erp_compute_erps);
    register_op(reg, 'erp_compute_ga',         @analysis.erp_compute_ga);
    register_op(reg, 'erp_define_contrast',    @analysis.erp_define_contrast);
    register_op(reg, 'erp_compute_stats',      @analysis.erp_compute_stats);
    register_op(reg, 'erp_plot_erp',           @analysis.erp_plot_erp);
    register_op(reg, 'erp_plot_contrast',      @analysis.erp_plot_contrast);
    register_op(reg, 'erp_plot_topo',          @analysis.erp_plot_topo);
    register_op(reg, 'erp_extract_feature',    @analysis.erp_extract_feature);
end
