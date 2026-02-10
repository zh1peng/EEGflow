function source = compute_spatial_filter(data, params, freqBand)
    % Compute LCMV beamformer spatial filters for one frequency band.
    % Expects FieldTrip epoched data as input.

    unit = 'mm';
    if isfield(params, 'Unit') && ~isempty(params.Unit)
        unit = char(string(params.Unit));
    end

    headmodel = load_headmodel(params, unit);

    % --- Source model ---
    pos = [];
    if isfield(params, 'SourcePos') && ~isempty(params.SourcePos)
        pos = params.SourcePos;
    else
        if ~isfield(params, 'AtlasPath') || isempty(params.AtlasPath)
            error('compute_spatial_filter:MissingAtlas', 'Provide params.SourcePos or params.AtlasPath.');
        end
        atlasT = readtable(params.AtlasPath);
        pos = atlas_table_to_pos(atlasT);
    end

    cfg = [];
    cfg.method = 'basedonpos';
    cfg.sourcemodel.pos = pos;
    cfg.unit = unit;
    cfg.headmodel = headmodel;
    sourcemodel_atlas = ft_prepare_sourcemodel(cfg);
    sourcemodel_atlas.coordsys = 'mni';
    
    %% Bandpass the data in the relevant frequency band
    cfg = [];
    cfg.bpfilter = 'yes';
    cfg.bpfreq = params.FreqBand.(freqBand);
    data = ft_preprocessing(cfg, data);
    
    %% Compute the covariance matrix from the data
    % First normalize time axis of the data (otherwise it cracks).
    % Here we loose the temporal order of the epochs
    temptime = data.time{1};
    [data.time{:}] = deal(temptime);
    
    % Compute the average covaraciance matrix from the sensor data
    cfg = [];
    cfg.covariance = 'yes';
    cfg.keeptrials = 'no';
    cfg.removemean = 'yes';
    tlock = ft_timelockanalysis(cfg,data);
    
    %%  Computation of the spatial filter
    % Forward model (leadfield)
    cfg = [];
    cfg.sourcemodel = sourcemodel_atlas;
    cfg.headmodel = headmodel;
    cfg.normalize = 'yes';
    lf = ft_prepare_leadfield(cfg, data);
    
    % Spatial filter
    cfg = [];
    cfg.method = 'lcmv';
    cfg.keeptrials = 'yes';
    cfg.lcmv.keepfilter = 'yes';
    cfg.lcmv.lambda = '5%';
    cfg.lcmv.fixedori = 'yes';
    cfg.lcmv.projectnoise = 'yes';
    cfg.lcmv.weightnorm = 'arraygain';
    % cfg.lcmv.weightnorm = 'nai';
    cfg.sourcemodel = lf;
    source = ft_sourceanalysis(cfg, tlock);
end
