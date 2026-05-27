function connMatrix = compute_dwpli(data, spatialFilter, params, freqBand)
    if nargin < 2, spatialFilter = []; end
    if nargin < 3 || isempty(params)
        params = struct();
    end
    params = rest.normalize_params(params);
    require_taper_dependency(params.Taper, 'rest.compute_dwpli');

    if ~isfield(params, 'FreqBand') || ~isstruct(params.FreqBand) || ~isfield(params.FreqBand, freqBand)
        error('rest:compute_dwpli:MissingFreqBand', 'params.FreqBand.%s is required.', char(string(freqBand)));
    end
    if numel(data.trial) < params.MinTrials
        error('rest:compute_dwpli:TooFewTrials', ...
            'Recording has %d epochs, below MinTrials=%d.', numel(data.trial), params.MinTrials);
    end
    
    p = params;
    p.BandName = char(string(freqBand));
    p.BandpassRange = params.FreqBand.(freqBand);
    if isempty(spatialFilter)
        cfg = [];
        cfg.bpfilter = 'yes';
        cfg.bpfreq = p.BandpassRange;
        virtChan_data = ft_preprocessing(cfg, data);
    else
        virtChan_data = source.reconstruct_virtual_channels(data, spatialFilter, p);
    end
    clear data spatialFilter;
    
    % Frequencies of interest
    fois = params.FreqBand.(freqBand)(1):params.FreqResConnectivity:params.FreqBand.(freqBand)(2);
    % Fourier components
    cfg = [];
    cfg.method = 'mtmfft';
    cfg.taper = params.Taper;
    cfg.output = 'fourier';
    cfg.keeptrials = 'yes';
    cfg.pad = 'nextpow2';
    cfg.foi = fois;
    cfg.tapsmofrq = params.Tapsmofrq;
    virtFreq = ft_freqanalysis(cfg, virtChan_data);
    clear virtChan_data;
    
    % Connectivity
    cfg = [];
    cfg.method = 'wpli_debiased';
    source_conn = ft_connectivityanalysis(cfg, virtFreq);
    clear virtFreq;
    
    % Average across frequency bins
    connMatrix = mean(abs(source_conn.wpli_debiasedspctrm),3);
    if all(all(isnan(connMatrix)))
        error('Connectivity matrix only contains NaN');
    end

end
