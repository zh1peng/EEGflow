function [sourceFilter, info] = compute_spatial_filter(data, params)
%COMPUTE_SPATIAL_FILTER Compute generic LCMV spatial filters.
%
% Unlike rest.compute_spatial_filter, this function is not tied to a
% resting-state frequency band. By default it uses the broadband epoched
% data covariance, making the filter reusable for source ERP/TF workflows.
%
% Required:
%   data   FieldTrip epoched raw struct.
%   params HeadModel/HeadModelPath and SourcePos or AtlasPath.

    if nargin < 2 || isempty(params), params = struct(); end
    local_require_fieldtrip();

    R = local_defaults(params);
    headmodel = load_headmodel(R, R.Unit);
    [pos, atlas] = local_resolve_positions(R);

    dataCov = data;
    if R.FilterData
        if isempty(R.BandpassRange)
            error('source:compute_spatial_filter:MissingBandpass', 'BandpassRange is required when FilterData=true.');
        end
        cfg = [];
        cfg.bpfilter = 'yes';
        cfg.bpfreq = R.BandpassRange;
        dataCov = ft_preprocessing(cfg, dataCov);
    end

    if R.NormalizeTrialTime && numel(dataCov.time) > 1
        t0 = dataCov.time{1};
        [dataCov.time{:}] = deal(t0);
    end

    cfg = [];
    cfg.method = 'basedonpos';
    cfg.sourcemodel.pos = double(pos);
    cfg.unit = R.Unit;
    cfg.headmodel = headmodel;
    sourcemodel = ft_prepare_sourcemodel(cfg);
    if ~isfield(sourcemodel, 'coordsys') || isempty(sourcemodel.coordsys)
        sourcemodel.coordsys = R.CoordSys;
    end

    cfg = [];
    cfg.covariance = 'yes';
    cfg.keeptrials = 'no';
    cfg.removemean = R.RemoveMean;
    if ~isempty(R.CovarianceWindow)
        cfg.latency = R.CovarianceWindow;
    end
    tlock = ft_timelockanalysis(cfg, dataCov);

    cfg = [];
    cfg.sourcemodel = sourcemodel;
    cfg.headmodel = headmodel;
    cfg.normalize = R.NormalizeLeadfield;
    leadfield = ft_prepare_leadfield(cfg, dataCov);

    cfg = [];
    cfg.method = R.Method;
    cfg.keeptrials = 'yes';
    cfg.sourcemodel = leadfield;
    cfg.headmodel = headmodel;
    cfg.lcmv.keepfilter = 'yes';
    cfg.lcmv.lambda = R.Lambda;
    cfg.lcmv.fixedori = R.FixedOrientation;
    cfg.lcmv.projectnoise = R.ProjectNoise;
    cfg.lcmv.weightnorm = R.WeightNorm;
    sourceFilter = ft_sourceanalysis(cfg, tlock);
    sourceFilter.unit = R.Unit;
    if ~isfield(sourceFilter, 'coordsys') || isempty(sourceFilter.coordsys)
        sourceFilter.coordsys = R.CoordSys;
    end

    info = struct();
    info.method = R.Method;
    info.unit = R.Unit;
    info.coordsys = R.CoordSys;
    info.n_positions = size(pos, 1);
    info.n_inside = numel(local_inside_indices(sourceFilter));
    info.filter_data = R.FilterData;
    info.bandpass_range = R.BandpassRange;
    info.covariance_window = R.CovarianceWindow;
    info.atlas = atlas;
end

function R = local_defaults(params)
    R = params;
    R.Unit = char(string(local_get(R, 'Unit', 'mm')));
    R.Method = char(string(local_get(R, 'SpatialFilterMethod', local_get(R, 'Method', 'lcmv'))));
    R.CoordSys = char(string(local_get(R, 'CoordSys', 'mni')));
    R.FilterData = logical(local_get(R, 'FilterData', false));
    R.BandpassRange = local_get(R, 'BandpassRange', []);
    R.SourceIndex = local_get(R, 'SourceIndex', []);
    R.CovarianceWindow = local_get(R, 'CovarianceWindow', []);
    R.NormalizeTrialTime = logical(local_get(R, 'NormalizeTrialTime', true));
    R.RemoveMean = char(string(local_get(R, 'RemoveMean', 'yes')));
    R.NormalizeLeadfield = char(string(local_get(R, 'NormalizeLeadfield', 'yes')));
    R.Lambda = char(string(local_get(R, 'Regularization', local_get(R, 'Lambda', '5%'))));
    R.OrientationMode = lower(char(string(local_get(R, 'OrientationMode', 'fixedori'))));
    R.FixedOrientation = local_yesno(local_get(R, 'FixedOrientation', strcmp(R.OrientationMode, 'fixedori')));
    R.ProjectNoise = char(string(local_get(R, 'ProjectNoise', 'yes')));
    R.WeightNorm = char(string(local_get(R, 'WeightNorm', 'arraygain')));
end

function [pos, atlas] = local_resolve_positions(R)
    atlas = [];
    atlasPath = char(string(local_get(R, 'AtlasPath', '')));
    atlasTemplate = char(string(local_get(R, 'AtlasTemplate', '')));
    if isempty(atlasPath) && ~isempty(atlasTemplate)
        atlasPath = source.atlas_default_path(atlasTemplate);
    end
    if ~isempty(atlasPath)
        atlas = source.atlas_load(atlasPath);
        if ~isempty(R.SourceIndex)
            atlas = local_subset_atlas(atlas, R.SourceIndex);
        end
    end
    if isfield(R, 'SourcePos') && ~isempty(R.SourcePos)
        pos = double(R.SourcePos);
        return;
    end
    if isempty(atlas)
        error('source:compute_spatial_filter:MissingSourcePos', 'Provide SourcePos or AtlasPath.');
    end
    pos = double(atlas.pos);
end

function atlas = local_subset_atlas(atlas, idx)
    idx = double(idx(:));
    idx = idx(isfinite(idx) & idx >= 1);
    idx = unique(floor(idx), 'stable');
    if isempty(idx)
        return;
    end
    n = size(atlas.pos, 1);
    if max(idx) > n
        error('source:compute_spatial_filter:BadSourceIndex', 'SourceIndex exceeds atlas row count.');
    end
    atlas.source_index = idx;
    atlas.pos = atlas.pos(idx, :);
    for f = {'roi_label','roi_name','hemi','network'}
        name = f{1};
        if isfield(atlas, name) && ~isempty(atlas.(name)) && numel(atlas.(name)) >= max(idx)
            atlas.(name) = atlas.(name)(idx);
        end
    end
end

function idx = local_inside_indices(sourceFilter)
    inside = sourceFilter.inside;
    if islogical(inside)
        idx = find(inside(:));
    else
        idx = double(inside(:));
    end
end

function local_require_fieldtrip()
    required = {'ft_prepare_sourcemodel','ft_timelockanalysis','ft_prepare_leadfield','ft_sourceanalysis'};
    for i = 1:numel(required)
        if exist(required{i}, 'file') ~= 2
            error('source:compute_spatial_filter:MissingFieldTrip', 'FieldTrip function %s is required.', required{i});
        end
    end
end

function v = local_get(s, field, default)
    v = default;
    if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
        v = s.(field);
    end
end

function s = local_yesno(v)
    if islogical(v)
        if v
            s = 'yes';
        else
            s = 'no';
        end
        return;
    end
    s = char(string(v));
end
