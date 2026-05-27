function connMatrix = compute_aec(data, spatialFilter, params, freqBand)
    if nargin < 2, spatialFilter = []; end
%COMPUTE_AEC Compute source-space amplitude envelope correlation (AEC).
%
% This computes orthogonalized AEC (Hipp et al., 2012, Nat Neurosci) on
% virtual channels reconstructed from a beamformer spatial filter:
%   1) band-pass filter sensor-space data in the requested band
%   2) reconstruct ROI time series using FieldTrip ft_virtualchannel
%   3) compute orthogonalized AEC per epoch via rest.aecConnectivity
%   4) average across epochs
%
% Inputs
%   data     : FieldTrip epoched sensor data (struct)
%   source   : FieldTrip source struct returned by rest.compute_spatial_filter
%   params   : params struct with fields .FreqBand.(freqBand)
%   freqBand : char/string, e.g. 'alpha'
%
% Output
%   connMatrix : [nROI x nROI] averaged AEC connectivity matrix.
%
% Attribution / origin
%   The underlying AEC implementation is adapted from DISCOVER-EEG custom
%   functions (CC BY 4.0). See rest.aecConnectivity for details.

    p = params;
    p.BandName = char(string(freqBand));
    p.BandpassRange = params.FreqBand.(freqBand);
    if isempty(spatialFilter)
        cfg = [];
        cfg.bpfilter = 'yes';
        cfg.bpfreq = p.BandpassRange;
        virtChan_data = ft_preprocessing(cfg, data);
    else
        virtChan_data = source.reconstruct_virtual_channels(data, spatialFilter, p);
    end

    % Compute orthogonalized AEC per epoch, then average across epochs.
    Cepoch = rest.aecConnectivity(virtChan_data, 'Verbose', false);
    connMatrix = mean(Cepoch, 3, 'omitnan');
end
