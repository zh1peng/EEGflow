function [power]=compute_power(data, params)

    % Average power spectrum across epochs in the range 1-100 Hz
    cfg = [];
    cfg.foilim = [1 100];
    cfg.method = 'mtmfft';
    cfg.taper = params.Taper;
    cfg.tapsmofrq = params.Tapsmofrq;
    if ~isempty(params.Pad)
        cfg.pad = params.Pad;
        cfg.padtype = 'zero';
    end
    cfg.output = 'pow';
    cfg.keeptrials ='no';
    power = ft_freqanalysis(cfg, data);
    end