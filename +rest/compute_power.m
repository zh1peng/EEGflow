function [power]=compute_power(data, params)

    if nargin < 2 || isempty(params)
        params = struct();
    end
    params = rest.normalize_params(params);
    require_taper_dependency(params.Taper, 'rest.compute_power');

    % Average power spectrum across epochs.
    cfg = [];
    cfg.method = 'mtmfft';
    cfg.taper = params.Taper;
    cfg.tapsmofrq = params.Tapsmofrq;
    if ~isempty(params.PowerFoi)
        cfg.foi = params.PowerFoi;
    elseif ~isempty(params.PowerFreqStep)
        cfg.foi = params.PowerFreqRange(1):params.PowerFreqStep:params.PowerFreqRange(2);
    else
        cfg.foilim = params.PowerFreqRange;
    end
    if ~isempty(params.Pad)
        cfg.pad = params.Pad;
        cfg.padtype = 'zero';
    end
    cfg.output = 'pow';
    cfg.keeptrials ='no';
    power = ft_freqanalysis(cfg, data);
    end
