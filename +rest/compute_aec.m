function [connMatrix]=compute_aec(data, source, params,  freqBand)
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

    if exist('aecConnectivity', 'file')
        connMatrix = aecConnectivity(virtChan_data);
        connMatrix = mean(connMatrix, 3);
        return;
    end

    % Fallback: simple amplitude envelope correlation (AEC) averaged across trials.
    connMatrix = local_aec_fallback(virtChan_data);
 
    end

function C = local_aec_fallback(data)
    % data: FieldTrip epoched data struct with .trial {1 x nTrials}, each [nChan x nTime]
    nTr = numel(data.trial);
    if nTr < 1
        error('compute_aec:BadData', 'No trials found.');
    end

    X1 = data.trial{1};
    nCh = size(X1, 1);
    Csum = zeros(nCh, nCh);

    for t = 1:nTr
        X = double(data.trial{t});
        if size(X, 1) ~= nCh
            error('compute_aec:BadData', 'Inconsistent channel count across trials.');
        end
        env = abs(local_analytic_signal(X)); % [ch x time]
        Ct = corrcoef(env.');                % [ch x ch]
        Csum = Csum + Ct;
    end

    C = Csum / nTr;
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
