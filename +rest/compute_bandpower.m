function bandpower = compute_bandpower(power, params)
%COMPUTE_BANDPOWER Compute sensor-space absolute and relative band power.
%
% Output fields are aligned with params.FreqBand. Each band contains
% per-channel absolute/relative power plus mean summaries for export.

    if ~isstruct(power) || ~isfield(power, 'freq') || ~isfield(power, 'powspctrm')
        error('rest:compute_bandpower:BadInput', 'power must have freq and powspctrm fields.');
    end
    if nargin < 2 || isempty(params)
        params = struct();
    end
    params = rest.normalize_params(params);
    if ~isfield(params, 'FreqBand') || ~isstruct(params.FreqBand) || isempty(fieldnames(params.FreqBand))
        error('rest:compute_bandpower:MissingFreqBand', 'params.FreqBand is required.');
    end

    freq = double(power.freq(:).');
    P = double(power.powspctrm);
    if ndims(P) ~= 2 || size(P, 2) ~= numel(freq)
        error('rest:compute_bandpower:BadShape', 'powspctrm must be nChan x nFreq.');
    end

    totalRange = params.PowerFreqRange;
    idxTotal = freq >= totalRange(1) & freq <= totalRange(2);
    if nnz(idxTotal) < 1
        idxTotal = true(size(freq));
    end
    totalPower = local_integrate(freq(idxTotal), P(:, idxTotal));
    totalPower(totalPower <= 0 | ~isfinite(totalPower)) = NaN;

    bands = fieldnames(params.FreqBand);
    bandpower = struct();
    for i = 1:numel(bands)
        band = bands{i};
        lim = double(params.FreqBand.(band)(:).');
        if numel(lim) ~= 2 || lim(2) <= lim(1)
            error('rest:compute_bandpower:BadBand', 'FreqBand.%s must be [fmin fmax].', band);
        end

        idx = freq >= lim(1) & freq <= lim(2);
        absPower = nan(size(P, 1), 1);
        if nnz(idx) >= 1
            absPower = local_integrate(freq(idx), P(:, idx));
        end

        relPower = absPower ./ totalPower;
        bandpower.(band).range_hz = lim;
        bandpower.(band).absolute = absPower(:);
        bandpower.(band).relative = relPower(:);
        bandpower.(band).absolute_mean = mean(absPower, 'omitnan');
        bandpower.(band).relative_mean = mean(relPower, 'omitnan');
    end
end

function v = local_integrate(freq, P)
    if numel(freq) == 1
        v = P(:, 1);
    else
        v = trapz(freq, P, 2);
    end
end
