function pow = compute_source_power(data, spatialFilter, params, freqBand)
%COMPUTE_SOURCE_POWER Rest wrapper for source.compute_source_power.

    if nargin < 2, spatialFilter = []; end
    if nargin < 3 || isempty(params), params = struct(); end
    if nargin < 4 || isempty(freqBand)
        error('rest:compute_source_power:MissingBand', 'freqBand is required.');
    end
    freqBand = char(string(freqBand));
    if ~isfield(params, 'FreqBand') || ~isfield(params.FreqBand, freqBand)
        error('rest:compute_source_power:BadBand', 'params.FreqBand.%s not found.', freqBand);
    end
    p = params;
    p.BandName = freqBand;
    p.BandpassRange = params.FreqBand.(freqBand);
    if isempty(spatialFilter)
        data = local_bandpass_source(data, p.BandpassRange);
        pow = source.compute_source_power(data);
    else
        pow = source.compute_source_power(data, spatialFilter, p);
    end
end

function src = local_bandpass_source(src, bandpassRange)
    if isempty(bandpassRange)
        return;
    end
    cfg = [];
    cfg.bpfilter = 'yes';
    cfg.bpfreq = bandpassRange;
    src = ft_preprocessing(cfg, src);
end
