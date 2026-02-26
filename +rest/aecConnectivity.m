function connMatrix = aecConnectivity(virtChan_timeSeries, varargin)
%AECCONNECTIVITY Orthogonalized amplitude envelope correlation (AEC).
%
% This computes orthogonalized AEC as described in Hipp et al. (2012,
% Nature Neuroscience) and commonly implemented in Brainstorm.
%
% Input
%   virtChan_timeSeries : FieldTrip-like epoched data struct with fields:
%       - .trial {1 x nEpoch} each [nChan x nTime]
%       - .label {nChan x 1}
%
% Output
%   connMatrix : [nChan x nChan x nEpoch] connectivity matrices per epoch.
%
% Options (name-value)
%   'Normalize'        : logical, default true
%       If true, divides by 0.577 (Hipp 2012) to compensate for
%       under-estimation due to orthogonalization.
%   'UseLogPower'      : logical, default true
%       If true, correlates log(power) envelopes: log(|x|^2 + Tol).
%       If false, correlates amplitude envelopes: |x|.
%   'Tol'              : numeric scalar, default 1e-8
%       Small constant added inside log power.
%   'ReplaceNonFinite' : logical, default true
%       If true, replaces non-finite correlations with 0.
%   'Verbose'          : logical, default false
%       If true, prints per-epoch timing.
%   'Eps'              : numeric scalar, default eps
%       Small constant used to avoid divide-by-zero in orthogonalization.
%
% Attribution / origin
%   This implementation is adapted from DISCOVER-EEG custom functions
%   (aecConnectivity.m), licensed under CC BY 4.0:
%     - Cristina Gil, Felix Bott, Stefan Dvoretskii (TUM), 2022
%   The code here was modified to:
%     - avoid external toolbox dependencies (no required Statistics toolbox)
%     - add optional verbosity and robustness controls
%     - use an internal analytic signal fallback if hilbert() is unavailable

    ip = inputParser;
    ip.addRequired('virtChan_timeSeries', @isstruct);
    ip.addParameter('Normalize', true, @(x) islogical(x) && isscalar(x));
    ip.addParameter('UseLogPower', true, @(x) islogical(x) && isscalar(x));
    ip.addParameter('Tol', 1e-8, @(x) isnumeric(x) && isscalar(x) && x >= 0);
    ip.addParameter('ReplaceNonFinite', true, @(x) islogical(x) && isscalar(x));
    ip.addParameter('Verbose', false, @(x) islogical(x) && isscalar(x));
    ip.addParameter('Eps', eps, @(x) isnumeric(x) && isscalar(x) && x > 0);
    ip.parse(virtChan_timeSeries, varargin{:});
    R = ip.Results;

    if ~isfield(virtChan_timeSeries, 'trial') || isempty(virtChan_timeSeries.trial)
        error('rest:aecConnectivity:BadInput', 'virtChan_timeSeries.trial is required.');
    end
    if ~isfield(virtChan_timeSeries, 'label') || isempty(virtChan_timeSeries.label)
        error('rest:aecConnectivity:BadInput', 'virtChan_timeSeries.label is required.');
    end

    nEpochs = numel(virtChan_timeSeries.trial);
    nChan = numel(virtChan_timeSeries.label);

    connMatrix = nan(nChan, nChan, nEpochs);

    for iEpoch = 1:nEpochs
        t0 = tic;

        X = virtChan_timeSeries.trial{iEpoch};
        if ~isnumeric(X) || ndims(X) ~= 2
            error('rest:aecConnectivity:BadTrial', 'trial{%d} must be a numeric 2D matrix.', iEpoch);
        end
        if size(X, 1) ~= nChan
            error('rest:aecConnectivity:BadTrial', 'trial{%d} has %d channels but label has %d.', iEpoch, size(X, 1), nChan);
        end

        % Analytic signal (complex). Prefer hilbert() if available.
        if exist('hilbert', 'file') ~= 0
            try
                HA = hilbert(double(X).').'; % [nChan x nTime]
            catch
                HA = local_analytic_signal(double(X));
            end
        else
            HA = local_analytic_signal(double(X));
        end

        absHA = abs(HA);

        Rmat = nan(nChan, nChan);
        for iSeed = 1:nChan
            seed = HA(iSeed, :);                % complex-valued (1 x nTime)
            seedAbs = abs(seed);
            phase = conj(seed) ./ (seedAbs + R.Eps); % avoid divide-by-zero

            % Orthogonalize all signals w.r.t. the seed.
            % Result is real-valued (nChan x nTime).
            HAo = imag(HA .* phase);

            % Avoid rounding errors (original heuristic, made safe).
            ratio = abs(HAo) ./ (absHA + R.Eps);
            HAo(ratio < 2 * eps) = 0;

            if R.UseLogPower
                seedFeat = log(seedAbs.^2 + R.Tol); % 1 x nTime
                tgtFeat  = log(abs(HAo).^2 + R.Tol); % nChan x nTime
            else
                seedFeat = seedAbs;   % 1 x nTime
                tgtFeat  = abs(HAo);  % nChan x nTime
            end

            c = local_corr_seed_to_rows(seedFeat, tgtFeat); % 1 x nChan
            Rmat(iSeed, :) = c;
        end

        % Average correlation in both directions (X->Y and Y->X).
        C = (Rmat + Rmat.') / 2;
        if R.ReplaceNonFinite
            C(~isfinite(C)) = 0;
        end
        connMatrix(:, :, iEpoch) = C;

        if R.Verbose
            fprintf('[rest.aecConnectivity] epoch %d/%d took %.2fs\n', iEpoch, nEpochs, toc(t0));
        end
    end

    if R.Normalize
        connMatrix = connMatrix ./ 0.577;
    end
end

% ----------------- local helpers -----------------
function r = local_corr_seed_to_rows(seedRow, rows)
    % Correlate one 1xT vector with each row of an NxT matrix (Pearson r).
    % Returns 1xN.
    s = double(seedRow(:).');   % 1 x T
    X = double(rows);           % N x T

    if size(X, 2) ~= numel(s)
        error('rest:aecConnectivity:BadShape', 'Target rows must have the same length as seed.');
    end

    s0 = s - mean(s, 2);
    X0 = X - mean(X, 2);

    ss = sqrt(sum(s0.^2, 2));
    sx = sqrt(sum(X0.^2, 2));   % N x 1

    denom = sx * ss;
    denom(denom == 0) = NaN;

    r = (X0 * s0.') ./ denom;   % N x 1
    r = r(:).';
end

function z = local_analytic_signal(x)
    % Compute analytic signal along 2nd dimension without toolbox dependencies.
    % x: [nChan x nTime] real
    n = size(x, 2);
    X = fft(x, [], 2);

    h = zeros(1, n);
    if mod(n, 2) == 0
        h(1) = 1;
        h(n/2 + 1) = 1;
        h(2:n/2) = 2;
    else
        h(1) = 1;
        h(2:(n + 1)/2) = 2;
    end

    z = ifft(X .* h, [], 2);
end

