function params = params_template()
%PARAMS_TEMPLATE Default parameter template for rest (legacy-compatible fields).
%
% This returns a struct with the same field names used by the legacy
% +rest/compute_* functions, but does not hardcode machine-specific paths.
%
% You are expected to fill in at least:
%   - params.HeadModelPath  OR params.HeadModel
%   - params.AtlasPath      (or provide params.SourcePos in refactored APIs)
%   - electrode positions (see params.TemplateElecFile / params.Elec)

    params = struct();

    % Minimum number of epochs/trials required for connectivity/source steps.
    params.nTrial_treshold = 10;

    % Spectral analysis
    params.FreqRes = 0.1;
    params.Pad = [];            % [] or numeric seconds or FieldTrip pad string
    params.Taper = 'dpss';
    params.Tapsmofrq = 1;

    % Frequency bands (Hz)
    params.FreqBand = struct();
    params.FreqBand.delta = [1 4];
    params.FreqBand.theta = [4 8];
    params.FreqBand.alpha = [8 12];
    params.FreqBand.beta  = [13 30];
    params.FreqBand.gamma = [30 45];

    % Source model / head model
    params.HeadModelPath = '';   % e.g., 'standard_bem.mat' containing variable 'vol'
    params.HeadModel = [];       % alternatively pass the loaded structure
    params.AtlasPath = '';       % centroid CSV for source grid (see compute_spatial_filter)

    % Electrode positions for FieldTrip leadfield (optional but required for beamforming)
    params.TemplateElecFile = ''; % e.g., 'GSN-HydroCel-128.sfp'
    params.Elec = [];             % alternatively pass a FieldTrip elec struct
    params.Unit = 'mm';

    % Connectivity analysis
    params.FreqResConnectivity = 0.5;

    % Aperiodic (1/f) analysis
    params.RemoveAperiodic = false;
    params.AperiodicFitRange = [2 40]; % Hz

    % GRETNA graph analysis
    params.GRETNA_s1 = 0.05;
    params.GRETNA_s2 = 0.3;
    params.GRETNA_deltas = 0.02;
    params.GRETNA_n = 1000;
end
