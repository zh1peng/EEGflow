function reg = init_registry()
%INIT_REGISTRY Build a generic source-space registry.

    reg = containers.Map('KeyType', 'char', 'ValueType', 'any');

    % I/O and optional rest segmentation are reused from prep.
    reg('load_set') = @prep.load_set;
    reg('save_set') = @prep.save_set;
    reg('segment_rest') = @prep.segment_rest;

    % Geometry and source-space virtual-channel operations.
    reg('check_headmodel') = @source.check_headmodel;
    reg('source_reconstruct_epochs') = @source.reconstruct_epochs;
    reg('source_parcellate') = @source.parcellate_timeseries;
    reg('source_qc_report') = @source.qc_report;
    reg('source_compute_erps') = @source.compute_erps;
    reg('source_extract_window_feature') = @source.extract_window_feature;
    reg('erp_compute_source_erps') = @analysis.erp_compute_source_erps;
    reg('erp_compute_source_contrast') = @analysis.erp_compute_source_contrast;
    reg('erp_extract_source_feature') = @analysis.erp_extract_source_feature;
    reg('erp_plot_source_waveform') = @analysis.erp_plot_source_waveform;
    reg('tf_compute_source') = @analysis.tf_compute_source;
    reg('tf_extract_source_feature') = @analysis.tf_extract_source_feature;
    reg('tf_plot_source') = @analysis.tf_plot_source;
end
