function R = normalize_params(params)
%NORMALIZE_PARAMS Normalize resting-state parameter aliases and defaults.
%
% This helper keeps legacy config fields working while exposing clearer
% names for newer code.

    if nargin < 1 || isempty(params)
        params = struct();
    end
    if ~isstruct(params)
        error('rest:normalize_params:BadInput', 'params must be a struct.');
    end

    R = params;

    if isfield(R, 'MinTrials') && ~isempty(R.MinTrials)
        R.nTrial_treshold = R.MinTrials;
    elseif isfield(R, 'nTrial_treshold') && ~isempty(R.nTrial_treshold)
        R.MinTrials = R.nTrial_treshold;
    else
        R.MinTrials = 10;
        R.nTrial_treshold = 10;
    end

    if isfield(R, 'PowerFreqStep') && ~isempty(R.PowerFreqStep)
        R.FreqRes = R.PowerFreqStep;
    elseif isfield(R, 'FreqRes') && ~isempty(R.FreqRes)
        R.PowerFreqStep = R.FreqRes;
    else
        R.PowerFreqStep = [];
    end

    if ~isfield(R, 'PowerFreqRange') || isempty(R.PowerFreqRange)
        R.PowerFreqRange = [1 100];
    else
        R.PowerFreqRange = double(R.PowerFreqRange(:).');
    end

    if ~isfield(R, 'PowerFoi')
        R.PowerFoi = [];
    elseif ~isempty(R.PowerFoi)
        R.PowerFoi = double(R.PowerFoi(:).');
    end

    if ~isfield(R, 'Taper') || isempty(R.Taper)
        R.Taper = 'dpss';
    end
    if ~isfield(R, 'Tapsmofrq') || isempty(R.Tapsmofrq)
        R.Tapsmofrq = 1;
    end
    if ~isfield(R, 'Pad')
        R.Pad = [];
    end

    if ~isfield(R, 'PeakBand') || isempty(R.PeakBand)
        if isfield(R, 'FreqBand') && isstruct(R.FreqBand) && isfield(R.FreqBand, 'alpha')
            R.PeakBand = 'alpha';
        else
            R.PeakBand = '';
        end
    else
        R.PeakBand = char(string(R.PeakBand));
    end

    if isfield(R, 'FreqBand') && isstruct(R.FreqBand)
        bands = fieldnames(R.FreqBand);
        for i = 1:numel(bands)
            band = bands{i};
            R.FreqBand.(band) = double(R.FreqBand.(band)(:).');
        end
    end
end
