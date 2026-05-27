function state = reconstruct_epochs(state, args, meta)
%RECONSTRUCT_EPOCHS Reconstruct epoched EEG into source/parcel time series.
%
% Output contract:
%   state.source.epochs.trial{t} = [nSourceOrParcel x nTime]
%
% This is the generic source-space equivalent of sensor-level epoched EEG:
% channels are replaced by source points or atlas parcel centroids.

    if nargin < 1 || isempty(state), state = struct(); end
    if nargin < 2 || isempty(args), args = struct(); end
    if nargin < 3 || isempty(meta), meta = struct(); end

    op = 'source_reconstruct_epochs';
    cfg0 = state_get_config(state, op);
    params = state_merge(cfg0, args);

    p = inputParser;
    p.addParameter('LogFile', '', @(s) ischar(s) || isstring(s));
    p.addParameter('OutputPath', '', @(s) ischar(s) || isstring(s));
    p.addParameter('OutputBaseName', '', @(s) ischar(s) || isstring(s));
    p.addParameter('SaveMat', false, @(x) islogical(x) && isscalar(x));
    p.addParameter('KeepInState', true, @(x) islogical(x) && isscalar(x));

    p.addParameter('HeadModelPath', '', @(s) ischar(s) || isstring(s));
    p.addParameter('HeadModelTemplate', '', @(s) ischar(s) || isstring(s));
    p.addParameter('HeadModel', [], @(x) isempty(x) || isstruct(x));
    p.addParameter('AtlasPath', '', @(s) ischar(s) || isstring(s));
    p.addParameter('AtlasTemplate', '', @(s) ischar(s) || isstring(s));
    p.addParameter('SourcePos', [], @(x) isempty(x) || (isnumeric(x) && size(x, 2) == 3));
    p.addParameter('SourceIndex', [], @(x) isempty(x) || (isnumeric(x) && isvector(x)));
    p.addParameter('ElectrodePath', '', @(s) ischar(s) || isstring(s));
    p.addParameter('ElectrodeTemplate', '', @(s) ischar(s) || isstring(s));
    p.addParameter('TemplateElecFile', '', @(s) ischar(s) || isstring(s));
    p.addParameter('Elec', [], @(x) isempty(x) || isstruct(x));
    p.addParameter('Unit', 'mm', @(s) ischar(s) || isstring(s));
    p.addParameter('UseCheckedHeadmodel', true, @(x) islogical(x) && isscalar(x));

    p.addParameter('OutputLevel', 'auto', @(s) ischar(s) || isstring(s));
    p.addParameter('SourceSignalMode', 'signed', @(s) ischar(s) || isstring(s));
    p.addParameter('KeepSourceFilter', false, @(x) islogical(x) && isscalar(x));
    p.addParameter('SpatialFilter', [], @(x) isempty(x) || isstruct(x));
    p.addParameter('SourceFilter', [], @(x) isempty(x) || isstruct(x));

    p.addParameter('Method', 'lcmv', @(s) ischar(s) || isstring(s));
    p.addParameter('SpatialFilterMethod', '', @(s) ischar(s) || isstring(s));
    p.addParameter('FilterData', false, @(x) islogical(x) && isscalar(x));
    p.addParameter('BandpassRange', [], @(x) isempty(x) || (isnumeric(x) && numel(x) == 2 && x(2) > x(1)));
    p.addParameter('CovarianceWindow', [], @(x) isempty(x) || (isnumeric(x) && numel(x) == 2 && x(2) > x(1)));
    p.addParameter('Regularization', '', @(s) ischar(s) || isstring(s));
    p.addParameter('OrientationMode', 'fixedori', @(s) ischar(s) || isstring(s));
    p.addParameter('Lambda', '5%', @(s) ischar(s) || isstring(s));
    p.addParameter('FixedOrientation', 'yes', @(s) ischar(s) || isstring(s) || islogical(s));
    p.addParameter('ProjectNoise', 'yes', @(s) ischar(s) || isstring(s));
    p.addParameter('WeightNorm', 'arraygain', @(s) ischar(s) || isstring(s));
    p.addParameter('NormalizeLeadfield', 'yes', @(s) ischar(s) || isstring(s));

    p.addParameter('FieldTripRoot', '', @(s) ischar(s) || isstring(s));
    p.addParameter('AutoAddDeps', true, @(x) islogical(x) && isscalar(x));

    params = local_inherit_checked_geometry(state, params);
    nv = state_struct2nv(params);
    p.parse(nv{:});
    R = p.Results;
    R.Unit = char(string(R.Unit));
    R.OutputLevel = lower(char(string(R.OutputLevel)));
    R.SourceSignalMode = lower(char(string(R.SourceSignalMode)));

    if isfield(meta, 'validate_only') && meta.validate_only
        state = state_update_history(state, op, local_strip_geometry_params(R), 'validated', struct());
        return;
    end

    state_require_eeg(state, op);
    local_maybe_add_fieldtrip(R);

    log_step(state, meta, R.LogFile, sprintf('[source.reconstruct_epochs] Reconstructing source epochs | method=%s | signal=%s', ...
        char(string(R.Method)), R.SourceSignalMode));

    data = source.eeglab_to_fieldtrip_epoched(state.EEG, R);
    [sourceFilter, filterInfo] = local_resolve_filter(R, data);
    insideIdx = local_inside_indices(sourceFilter);

    cfg = [];
    cfg.pos = sourceFilter.pos(insideIdx, :);
    virt = ft_virtualchannel(cfg, data, sourceFilter);

    src = local_build_source_epochs(virt, sourceFilter, insideIdx, R, filterInfo);
    out = struct();
    out.n_trials = numel(src.trial);
    out.n_sources = numel(src.label);
    out.n_time = size(src.trial{1}, 2);
    out.level = src.level;
    out.signal_mode = src.signal_mode;

    if R.KeepInState
        if ~isfield(state, 'source') || ~isstruct(state.source)
            state.source = struct();
        end
        state.source.epochs = src;
        if ~isfield(state.source, 'qc') || ~isstruct(state.source.qc)
            state.source.qc = struct();
        end
        state.source.qc.signal = local_signal_qc(src);
        if R.KeepSourceFilter
            state.source.spatial_filter = sourceFilter;
        end
    end

    if R.SaveMat
        outDir = char(string(R.OutputPath));
        if isempty(outDir), outDir = local_cfg_fallback(state, {'Output','filepath'}, pwd); end
        if ~exist(outDir, 'dir'), mkdir(outDir); end
        baseName = char(string(R.OutputBaseName));
        if isempty(baseName) && isfield(state.EEG, 'setname') && ~isempty(state.EEG.setname)
            baseName = char(string(state.EEG.setname));
        end
        if isempty(baseName), baseName = 'unnamed'; end
        outFile = fullfile(outDir, sprintf('%s_source_epochs.mat', baseName));
        save(outFile, 'src', '-v7.3');
        out.output_file = outFile;
    end

    state = state_update_history(state, op, local_strip_geometry_params(R), 'success', out);
end

function src = local_build_source_epochs(virt, sourceFilter, insideIdx, R, filterInfo)
    mode = R.SourceSignalMode;
    trial = virt.trial;
    for t = 1:numel(trial)
        X = double(trial{t});
        switch mode
            case 'signed'
                % keep FieldTrip's fixed-orientation signed signal
            case 'absolute'
                X = abs(X);
            case {'rms','vectornorm'}
                X = sqrt(X.^2);
            case 'power'
                X = X.^2;
            otherwise
                error('source:reconstruct_epochs:BadSignalMode', ...
                    'Unsupported SourceSignalMode=%s. Use signed, absolute, rms, vectornorm, or power.', mode);
        end
        trial{t} = X;
    end

    level = R.OutputLevel;
    if strcmp(level, 'auto')
        if isstruct(filterInfo) && isfield(filterInfo, 'atlas') && ~isempty(filterInfo.atlas)
            level = 'parcel';
        else
            level = 'source';
        end
    end

    labels = local_source_labels(numel(insideIdx), insideIdx, filterInfo, level);

    src = struct();
    src.label = labels(:);
    src.trial = trial;
    src.time = virt.time;
    src.fsample = virt.fsample;
    src.level = level;
    src.source_pos = double(sourceFilter.pos(insideIdx, :));
    src.source_inside_idx = insideIdx(:);
    src.unit = R.Unit;
    src.method = char(string(R.Method));
    src.signal_mode = mode;
    src.cfg = local_strip_geometry_params(R);

    if isstruct(filterInfo) && isfield(filterInfo, 'atlas') && ~isempty(filterInfo.atlas)
        src.parcellation = local_parcellation_from_atlas(filterInfo.atlas, insideIdx, src.source_pos);
        src.atlas = filterInfo.atlas.path;
    end
end

function labels = local_source_labels(n, insideIdx, filterInfo, level)
    labels = arrayfun(@(i) sprintf('%s%03d', level, i), (1:n)', 'UniformOutput', false);
    if ~isstruct(filterInfo) || ~isfield(filterInfo, 'atlas') || isempty(filterInfo.atlas)
        return;
    end
    atlas = filterInfo.atlas;
    if isfield(atlas, 'roi_name') && ~isempty(atlas.roi_name) && numel(atlas.roi_name) >= max(insideIdx)
        labels = atlas.roi_name(insideIdx);
    end
end

function parc = local_parcellation_from_atlas(atlas, insideIdx, pos)
    parc = struct();
    parc.idx_in_atlas = insideIdx(:);
    parc.pos = pos;
    if isfield(atlas, 'roi_name') && numel(atlas.roi_name) >= max(insideIdx)
        parc.roi_name = atlas.roi_name(insideIdx);
    else
        parc.roi_name = arrayfun(@(i) sprintf('ROI%03d', i), (1:numel(insideIdx))', 'UniformOutput', false);
    end
    if isfield(atlas, 'hemi') && numel(atlas.hemi) >= max(insideIdx)
        parc.hemi = atlas.hemi(insideIdx);
    end
    if isfield(atlas, 'network') && numel(atlas.network) >= max(insideIdx)
        parc.network = atlas.network(insideIdx);
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

function [sourceFilter, filterInfo] = local_resolve_filter(R, data)
    sourceFilter = R.SpatialFilter;
    if isempty(sourceFilter)
        sourceFilter = R.SourceFilter;
    end
    if isempty(sourceFilter)
        [sourceFilter, filterInfo] = source.compute_spatial_filter(data, R);
        return;
    end

    filterInfo = struct();
    filterInfo.method = char(string(R.Method));
    filterInfo.unit = R.Unit;
    filterInfo.atlas = [];
    if isfield(sourceFilter, 'rest_filter_info')
        filterInfo = sourceFilter.rest_filter_info;
    end
end

function qc = local_signal_qc(src)
    nTrial = numel(src.trial);
    finiteTrial = false(nTrial, 1);
    vars = nan(numel(src.label), nTrial);
    for t = 1:nTrial
        X = double(src.trial{t});
        finiteTrial(t) = all(isfinite(X(:)));
        vars(:, t) = var(X, 0, 2, 'omitnan');
    end
    qc = struct();
    qc.n_trial = nTrial;
    qc.n_signal = numel(src.label);
    qc.all_finite = all(finiteTrial);
    qc.bad_trial = find(~finiteTrial);
    qc.variance_median = median(vars(:), 'omitnan');
    qc.variance_p95 = prctile(vars(:), 95);
end

function params = local_inherit_checked_geometry(state, params)
    if nargin < 2 || isempty(params), params = struct(); end
    useChecked = true;
    if isfield(params, 'UseCheckedHeadmodel') && ~isempty(params.UseCheckedHeadmodel)
        useChecked = logical(params.UseCheckedHeadmodel);
    end
    if ~useChecked || ~isstruct(state), return; end

    geom = [];
    if isfield(state, 'source') && isstruct(state.source) && isfield(state.source, 'geometry')
        geom = state.source.geometry;
    elseif isfield(state, 'rest') && isstruct(state.rest) && isfield(state.rest, 'headmodel')
        geom = state.rest.headmodel;
    end
    if isempty(geom), return; end

    if isfield(geom, 'headmodel') && ~isempty(geom.headmodel) && (~isfield(params, 'HeadModel') || isempty(params.HeadModel))
        params.HeadModel = geom.headmodel;
    end
    if isfield(geom, 'elec') && ~isempty(geom.elec) && (~isfield(params, 'Elec') || isempty(params.Elec))
        params.Elec = geom.elec;
    end
    if isfield(geom, 'unit') && ~isempty(geom.unit) && (~isfield(params, 'Unit') || isempty(params.Unit))
        params.Unit = geom.unit;
    end
end

function local_maybe_add_fieldtrip(R)
    if ~R.AutoAddDeps
        return;
    end
    if exist('ft_virtualchannel', 'file') == 2
        return;
    end
    ftRoot = char(string(R.FieldTripRoot));
    if isempty(ftRoot), ftRoot = getenv('FIELDTRIP_ROOT'); end
    if ~isempty(ftRoot) && isfolder(ftRoot)
        addpath(ftRoot);
        if exist('ft_defaults', 'file') == 2
            try
                ft_defaults;
            catch
            end
        end
    end
end

function params = local_strip_geometry_params(params)
    params = state_strip_eeg_param(params);
    for f = {'HeadModel','Elec','SpatialFilter','SourceFilter'}
        if isfield(params, f{1})
            params.(f{1}) = [];
        end
    end
end

function v = local_cfg_fallback(state, path, default)
    v = default;
    if ~isstruct(state) || ~isfield(state, 'cfg') || ~isstruct(state.cfg)
        return;
    end
    t = state.cfg;
    for i = 1:numel(path)
        f = path{i};
        if ~isstruct(t) || ~isfield(t, f)
            return;
        end
        t = t.(f);
    end
    v = t;
    if isstring(v), v = char(v); end
end
