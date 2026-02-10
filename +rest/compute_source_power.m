function pow = compute_source_power(data, source, params, freqBand)
%COMPUTE_SOURCE_POWER Estimate band-limited source power at ROI centroids.
%
% This computes a simple per-ROI power estimate by:
%   1) band-pass filtering the sensor-space data in the requested band
%   2) reconstructing virtual channels using the LCMV spatial filters
%   3) averaging mean-square amplitude across time and trials
%
% Inputs:
%   data     : FieldTrip epoched sensor data (struct)
%   source   : FieldTrip source struct returned by rest.compute_spatial_filter
%   params   : params struct with fields .FreqBand.(freqBand)
%   freqBand : char/string, e.g. 'alpha'
%
% Output:
%   pow : [nROI x 1] power values for inside nodes, ordered as
%         source.pos(source.inside,:).
%
% Notes:
% - This is meant for visualization/reporting. It is not identical to
%   beamformer "source.pow" fields computed internally by FieldTrip.

    if ~isfield(params, 'FreqBand') || ~isfield(params.FreqBand, freqBand)
        error('rest:compute_source_power:BadBand', 'params.FreqBand.%s not found.', char(string(freqBand)));
    end
    if ~isstruct(source) || ~isfield(source, 'pos') || ~isfield(source, 'inside')
        error('rest:compute_source_power:BadSource', 'source must have fields .pos and .inside.');
    end

    inside = logical(source.inside(:));
    if ~any(inside)
        pow = [];
        return;
    end

    % Band-pass filter.
    cfg = [];
    cfg.bpfilter = 'yes';
    cfg.bpfreq = params.FreqBand.(freqBand);
    dataBp = ft_preprocessing(cfg, data);

    % Virtual channels at inside positions (ROI centroids).
    cfg = [];
    cfg.pos = source.pos(inside, :);
    virt = ft_virtualchannel(cfg, dataBp, source);

    nTr = numel(virt.trial);
    if nTr < 1
        error('rest:compute_source_power:BadData', 'No trials found in virtual channel data.');
    end

    X1 = double(virt.trial{1});
    nCh = size(X1, 1);
    pSum = zeros(nCh, 1);
    for t = 1:nTr
        X = double(virt.trial{t});
        if size(X, 1) ~= nCh
            error('rest:compute_source_power:BadData', 'Inconsistent channel count across trials.');
        end
        % Mean-square amplitude as a simple "power" proxy.
        pSum = pSum + mean(X.^2, 2, 'omitnan');
    end
    pow = pSum / nTr;
end

