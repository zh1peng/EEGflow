function reg = init_registry()
%INIT_REGISTRY Build a rest-only registry (op -> function_handle).
%
% Notes:
%   The REST module is designed as "prep-like" middleware: steps take and
%   return a state struct (state.EEG + optional state.rest outputs).

    reg = containers.Map('KeyType', 'char', 'ValueType', 'any');

    % Optional: reuse prep I/O so a rest pipeline can be standalone.
    reg('load_set') = @prep.load_set;
    reg('save_set') = @prep.save_set;
    reg('segment_rest') = @prep.segment_rest;

    % Rest feature extraction
    reg('check_headmodel') = @rest.check_headmodel;
    reg('source_reconstruct_epochs') = @source.reconstruct_epochs;
    reg('source_parcellate') = @source.parcellate_timeseries;
    reg('source_qc_report') = @source.qc_report;
    reg('source_compute_erps') = @source.compute_erps;
    reg('source_extract_window_feature') = @source.extract_window_feature;
    reg('compute_all_features') = @rest.compute_all_features;
end
