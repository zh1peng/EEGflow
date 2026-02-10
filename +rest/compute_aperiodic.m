function [aperiodic, power_osc] = compute_aperiodic(power, params)
%COMPUTE_APERIODIC Fit and remove the aperiodic (1/f) component from PSD.
%
% This is a lightweight, dependency-free approximation of "aperiodic
% corrected" spectra commonly used in resting-state feature pipelines.
%
% Inputs
%   power  FieldTrip freq struct (e.g., from ft_freqanalysis) with fields:
%          - power.freq (1 x nFreq)
%          - power.powspctrm (nChan x nFreq)
%   params struct with optional fields:
%          - AperiodicFitRange (1x2) default [2 40] (Hz)
%
% Outputs
%   aperiodic struct
%     - method: 'loglog_polyfit'
%     - fit_range_hz
%     - exponent (nChan x 1): positive exponent (power ~ 1/f^exponent)
%     - offset   (nChan x 1): log10 power at 1 Hz (intercept at log10(f)=0)
%     - r2       (nChan x 1): goodness of fit in log-log space
%     - exponent_mean / offset_mean / r2_mean
%   power_osc FieldTrip freq struct matching input, with powspctrm replaced
%            by the flattened spectrum (power divided by fitted 1/f).

    if ~isstruct(power) || ~isfield(power, 'freq') || ~isfield(power, 'powspctrm')
        error('rest:compute_aperiodic:BadInput', 'power must be a FieldTrip freq struct with freq and powspctrm.');
    end

    fitRange = [2 40];
    if nargin >= 2 && isstruct(params) && isfield(params, 'AperiodicFitRange') && ~isempty(params.AperiodicFitRange)
        fitRange = double(params.AperiodicFitRange(:).');
    end
    if numel(fitRange) ~= 2 || ~all(isfinite(fitRange)) || fitRange(1) <= 0 || fitRange(2) <= fitRange(1)
        error('rest:compute_aperiodic:BadFitRange', 'AperiodicFitRange must be [fmin fmax] with fmin>0 and fmax>fmin.');
    end

    freq = double(power.freq(:).');
    if any(freq <= 0)
        error('rest:compute_aperiodic:BadFreq', 'power.freq must be strictly positive for log-log fitting.');
    end

    P = double(power.powspctrm);
    if ndims(P) ~= 2
        error('rest:compute_aperiodic:BadPowShape', 'power.powspctrm must be nChan x nFreq (got %s).', mat2str(size(P)));
    end
    if size(P, 2) ~= numel(freq)
        error('rest:compute_aperiodic:BadPowShape', 'powspctrm second dimension must match numel(freq).');
    end

    idx = freq >= fitRange(1) & freq <= fitRange(2);
    if nnz(idx) < 5
        error('rest:compute_aperiodic:TooFewBins', 'Too few frequency bins in AperiodicFitRange=[%g %g].', fitRange(1), fitRange(2));
    end

    logf_fit = log10(freq(idx));

    nChan = size(P, 1);
    slope = nan(nChan, 1);
    intercept = nan(nChan, 1);
    r2 = nan(nChan, 1);

    % Fit y = intercept + slope*log10(f) per channel in log-log space.
    for c = 1:nChan
        y = log10(max(P(c, idx), eps));
        coef = polyfit(logf_fit, y, 1);
        slope(c) = coef(1);
        intercept(c) = coef(2);

        yhat = polyval(coef, logf_fit);
        ss_res = sum((y - yhat).^2);
        ss_tot = sum((y - mean(y)).^2);
        if ss_tot > 0
            r2(c) = 1 - ss_res / ss_tot;
        else
            r2(c) = NaN;
        end
    end

    % Build the fitted aperiodic component across the full frequency axis.
    logf_all = log10(freq);
    fitLogPow = intercept + slope .* logf_all; % implicit expansion (nChan x nFreq)
    fitPow = 10 .^ fitLogPow;

    power_osc = power;
    power_osc.powspctrm = P ./ fitPow;
    try
        if ~isfield(power_osc, 'cfg') || ~isstruct(power_osc.cfg)
            power_osc.cfg = struct();
        end
        power_osc.cfg.aperiodic_removed = true;
        power_osc.cfg.aperiodic_fit_range_hz = fitRange;
    catch
        % best-effort only
    end

    aperiodic = struct();
    aperiodic.method = 'loglog_polyfit';
    aperiodic.fit_range_hz = fitRange;
    aperiodic.exponent = -slope;
    aperiodic.offset = intercept;
    aperiodic.r2 = r2;
    aperiodic.exponent_mean = mean(aperiodic.exponent, 'omitnan');
    aperiodic.offset_mean = mean(aperiodic.offset, 'omitnan');
    aperiodic.r2_mean = mean(aperiodic.r2, 'omitnan');
end

