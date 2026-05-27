function sourceFilter = compute_spatial_filter(data, params, freqBand)
%COMPUTE_SPATIAL_FILTER Resting-state wrapper for source.compute_spatial_filter.

    if nargin < 3 || isempty(freqBand)
        error('rest:compute_spatial_filter:MissingBand', 'freqBand is required.');
    end
    freqBand = char(string(freqBand));
    if ~isfield(params, 'FreqBand') || ~isfield(params.FreqBand, freqBand)
        error('rest:compute_spatial_filter:UnknownBand', 'FreqBand.%s is not defined.', freqBand);
    end

    p = params;
    p.FilterData = true;
    p.BandpassRange = params.FreqBand.(freqBand);
    if ~isfield(p, 'SpatialFilterMethod') || isempty(p.SpatialFilterMethod)
        p.SpatialFilterMethod = 'lcmv';
    end

    [sourceFilter, info] = source.compute_spatial_filter(data, p);
    sourceFilter.rest_band = freqBand;
    sourceFilter.rest_filter_info = info;
end
