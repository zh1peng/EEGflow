function state = tf_init(dataset)
    if ~isa(dataset, 'analysis.Dataset')
        error('Input must be an analysis.Dataset');
    end
    if ~isfield(dataset.data, 'meta') || ~isfield(dataset.data.meta, 'freqs') || ~isfield(dataset.data.meta, 'times')
        error('Dataset must contain TFD metadata (freqs/times).');
    end

    state = struct();
    state.Dataset = dataset;
    state.Selection = struct( ...
        'Groups', struct(), ...
        'Conditions', {{}}, ...
        'ROIs', struct(), ...
        'TimeWindows', struct(), ...
        'FreqBands', struct());
    state.Results = struct('GA_TFD', struct(), 'Contrasts', struct(), 'TF', struct());
end
