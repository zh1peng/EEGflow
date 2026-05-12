function [peakfrequency] = compute_peakfrequency(power, params)
%COMPUTE_PEAKFREQUENCY Estimate dominant frequency within a configured band.

if nargin < 2 || isempty(params)
    params = struct();
end
params = rest.normalize_params(params);

if ~isstruct(power) || ~isfield(power, 'freq') || ~isfield(power, 'powspctrm')
    error('rest:compute_peakfrequency:BadInput', 'power must have freq and powspctrm fields.');
end
if ~isfield(params, 'FreqBand') || ~isstruct(params.FreqBand)
    error('rest:compute_peakfrequency:MissingFreqBand', 'params.FreqBand is required.');
end

bandName = char(string(params.PeakBand));
if isempty(bandName)
    if isfield(params.FreqBand, 'alpha')
        bandName = 'alpha';
    else
        bands = fieldnames(params.FreqBand);
        bandName = bands{1};
    end
end
if ~isfield(params.FreqBand, bandName)
    error('rest:compute_peakfrequency:MissingPeakBand', 'FreqBand.%s is required.', bandName);
end

freq = double(power.freq(:).');
P = double(power.powspctrm);
if ndims(P) ~= 2 || size(P, 2) ~= numel(freq)
    error('rest:compute_peakfrequency:BadShape', 'powspctrm must be nChan x nFreq.');
end

avgpow = mean(P, 1, 'omitnan');
rangeHz = double(params.FreqBand.(bandName)(:).');
freqRange = find(freq >= rangeHz(1) & freq <= rangeHz(2));

peakfrequency = struct();
peakfrequency.band = bandName;
peakfrequency.range_hz = rangeHz;
peakfrequency.localmax = NaN;
peakfrequency.cog = NaN;
peakfrequency.peak_found = false;

if isempty(freqRange)
    return;
end

x = freq(freqRange);
y = avgpow(freqRange);
valid = isfinite(x) & isfinite(y);
x = x(valid);
y = y(valid);
if isempty(x) || all(y <= 0)
    return;
end

idxPeak = local_strongest_local_peak(y);
if isempty(idxPeak)
    [~, idxPeak] = max(y);
end

peakfrequency.localmax = x(idxPeak);
den = sum(y);
if den > 0
    peakfrequency.cog = sum(y .* x) / den;
end
peakfrequency.peak_found = isfinite(peakfrequency.localmax);
end

function idx = local_strongest_local_peak(y)
idx = [];
if numel(y) < 3
    return;
end
isPeak = false(size(y));
isPeak(2:end-1) = y(2:end-1) >= y(1:end-2) & y(2:end-1) >= y(3:end) & ...
                  (y(2:end-1) > y(1:end-2) | y(2:end-1) > y(3:end));
candidate = find(isPeak);
if isempty(candidate)
    return;
end
[~, k] = max(y(candidate));
idx = candidate(k);
end
