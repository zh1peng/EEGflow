function register_analysis(reg)
    register_op(reg, 'define_group',      @analysis.define_group);
    register_op(reg, 'select_conditions', @analysis.select_conditions);
    register_op(reg, 'compute_erps',      @analysis.compute_erps);
    register_op(reg, 'compute_ga',        @analysis.compute_ga);
    register_op(reg, 'compute_stats',     @analysis.compute_stats);
    register_op(reg, 'plot_erp',          @analysis.plot_erp);
end
