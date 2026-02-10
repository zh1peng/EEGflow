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
    reg('compute_all_features') = @rest.compute_all_features;
end
