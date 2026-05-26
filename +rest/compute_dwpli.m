function [connMatrix]=compute_dwpli(data, source,params, freqBand)
    if nargin < 3 || isempty(params)
        params = struct();
    end
    params = rest.normalize_params(params);
    require_taper_dependency(params.Taper, 'rest.compute_dwpli');

    if ~isfield(params, 'FreqBand') || ~isstruct(params.FreqBand) || ~isfield(params.FreqBand, freqBand)
        error('rest:compute_dwpli:MissingFreqBand', 'params.FreqBand.%s is required.', char(string(freqBand)));
    end
    if size(data.trial, 2) < params.MinTrials
        error('rest:compute_dwpli:TooFewTrials', ...
            'Recording has %d epochs, below MinTrials=%d.', size(data.trial, 2), params.MinTrials);
    end
    
    % Band-pass filter the data in the relevant frequency band
    cfg = [];
    cfg.bpfilter = 'yes';
    cfg.bpfreq = params.FreqBand.(freqBand);
    data = ft_preprocessing(cfg, data);
    
   
    % Reconstruct the virtual time series (apply spatial filter to sensor level
    % data)
    cfg  = [];
    cfg.pos = source.pos(source.inside,:);
    virtChan_data = ft_virtualchannel(cfg,data,source);
    clear data source;
    
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
