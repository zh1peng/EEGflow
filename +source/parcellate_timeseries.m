function state = parcellate_timeseries(state, args, meta)
%PARCELLATE_TIMESERIES Convert source-point epochs to parcel epochs.
%
% Input:
%   state.source.epochs.trial{t} = [nSource x nTime]
%
% Output:
%   state.source.parcel_epochs.trial{t} = [nParcel x nTime]

    if nargin < 1 || isempty(state), state = struct(); end
    if nargin < 2 || isempty(args), args = struct(); end
    if nargin < 3 || isempty(meta), meta = struct(); end

    op = 'source_parcellate';
    cfg0 = state_get_config(state, op);
    params = state_merge(cfg0, args);

    p = inputParser;
    p.addParameter('LogFile', '', @(s) ischar(s) || isstring(s));
    p.addParameter('InputField', 'epochs', @(s) ischar(s) || isstring(s));
    p.addParameter('OutputField', 'parcel_epochs', @(s) ischar(s) || isstring(s));
    p.addParameter('AtlasPath', '', @(s) ischar(s) || isstring(s));
    p.addParameter('AtlasTemplate', '', @(s) ischar(s) || isstring(s));
    p.addParameter('Parcellation', [], @(x) isempty(x) || isvector(x) || iscellstr(x) || isstring(x) || iscategorical(x));
    p.addParameter('ParcelLabels', {}, @(x) isempty(x) || iscellstr(x) || isstring(x));
    p.addParameter('Method', 'mean', @(s) ischar(s) || isstring(s));
    p.addParameter('KeepInState', true, @(x) islogical(x) && isscalar(x));

    nv = state_struct2nv(params);
    p.parse(nv{:});
    R = p.Results;
    R.InputField = char(string(R.InputField));
    R.OutputField = char(string(R.OutputField));
    R.Method = lower(char(string(R.Method)));

    if isfield(meta, 'validate_only') && meta.validate_only
        state = state_update_history(state, op, R, 'validated', struct());
        return;
    end

    if ~isfield(state, 'source') || ~isstruct(state.source) || ...
            ~isfield(state.source, R.InputField)
        error('source:parcellate_timeseries:MissingInput', ...
            'state.source.%s is required.', R.InputField);
    end

    src = state.source.(R.InputField);
    if isfield(src, 'level') && strcmpi(src.level, 'parcel')
        parcel = src;
        parcel.level = 'parcel';
        if ~isfield(parcel, 'qc')
            parcel.qc = struct('n_source', numel(parcel.label), ...
                'n_parcel', numel(parcel.label), 'coverage', 1, 'method', 'none');
        end
    else
        [parcelId, parcelMeta] = local_resolve_parcellation(src, R);
        parcel = local_apply_parcellation(src, parcelId, parcelMeta, R);
    end

    if R.KeepInState
        state.source.(R.OutputField) = parcel;
        state.source.epochs = parcel;
        if ~isfield(state.source, 'qc') || ~isstruct(state.source.qc)
            state.source.qc = struct();
        end
        state.source.qc.parcellation = parcel.qc;
    end

    qc = parcel.qc;
    log_step(state, meta, R.LogFile, sprintf( ...
        '[source.parcellate_timeseries] %d source(s) -> %d parcel(s), coverage=%.1f%%', ...
        qc.n_source, qc.n_parcel, 100 * qc.coverage));
    state = state_update_history(state, op, R, 'success', qc);
end

function [parcelId, meta] = local_resolve_parcellation(src, R)
    nSource = numel(src.label);
    if ~isempty(R.Parcellation)
        parcelId = string(R.Parcellation(:));
        if numel(parcelId) ~= nSource
            error('source:parcellate_timeseries:BadParcellation', ...
                'Parcellation length must match number of source signals.');
        end
        meta = local_meta_from_ids(parcelId, R.ParcelLabels);
        return;
    end

    atlasPath = char(string(R.AtlasPath));
    atlasTemplate = char(string(R.AtlasTemplate));
    if isempty(atlasPath) && ~isempty(atlasTemplate)
        atlasPath = source.atlas_default_path(atlasTemplate);
    end
    if isempty(atlasPath) && isfield(src, 'atlas') && ~isempty(src.atlas)
        atlasPath = char(string(src.atlas));
    end
    if isempty(atlasPath)
        error('source:parcellate_timeseries:MissingAtlas', ...
            'Provide Parcellation or AtlasPath.');
    end
    if ~isfield(src, 'source_pos') || isempty(src.source_pos)
        error('source:parcellate_timeseries:MissingSourcePos', ...
            'Atlas-based parcellation requires src.source_pos.');
    end

    atlas = source.atlas_load(atlasPath);
    nearest = local_nearest_rows(double(src.source_pos), double(atlas.pos));
    if isfield(atlas, 'roi_name') && ~isempty(atlas.roi_name)
        parcelId = string(atlas.roi_name(nearest));
    elseif isfield(atlas, 'roi_label') && ~isempty(atlas.roi_label)
        parcelId = string(atlas.roi_label(nearest));
    else
        parcelId = "parcel_" + string(nearest);
    end
    meta = local_meta_from_atlas(atlas, nearest);
end

function parcel = local_apply_parcellation(src, parcelId, meta, R)
    labels = unique(parcelId, 'stable');
    group = zeros(numel(parcelId), 1);
    for i = 1:numel(labels)
        group(parcelId == labels(i)) = i;
    end
    nParcel = numel(labels);
    trial = cell(size(src.trial));
    for t = 1:numel(src.trial)
        X = double(src.trial{t});
        Y = nan(nParcel, size(X, 2));
        for p = 1:nParcel
            rows = find(group == p);
            switch R.Method
                case 'mean'
                    Y(p, :) = mean(X(rows, :), 1, 'omitnan');
                case 'rms'
                    Y(p, :) = sqrt(mean(X(rows, :).^2, 1, 'omitnan'));
                case 'first_pc'
                    Y(p, :) = local_first_pc(X(rows, :));
                otherwise
                    error('source:parcellate_timeseries:BadMethod', ...
                        'Method must be mean, rms, or first_pc.');
            end
        end
        trial{t} = Y;
    end

    parcel = src;
    parcel.label = cellstr(labels(:));
    parcel.trial = trial;
    parcel.level = 'parcel';
    parcel.parcellation = local_subset_meta(meta, labels);
    parcel.cfg = R;
    parcel.qc = struct( ...
        'n_source', numel(parcelId), ...
        'n_parcel', nParcel, ...
        'coverage', mean(~ismissing(parcelId) & parcelId ~= ""), ...
        'method', R.Method);
end

function y = local_first_pc(X)
    if size(X, 1) == 1
        y = X;
        return;
    end
    X = X - mean(X, 2, 'omitnan');
    [~, ~, V] = svd(X', 'econ');
    y = V(:, 1)' * X;
end

function idx = local_nearest_rows(pos, ref)
    idx = nan(size(pos, 1), 1);
    for i = 1:size(pos, 1)
        [~, idx(i)] = min(sum((ref - pos(i, :)).^2, 2));
    end
end

function meta = local_meta_from_ids(parcelId, labels)
    labels = string(labels(:));
    if isempty(labels)
        labels = unique(parcelId, 'stable');
    end
    meta = struct();
    meta.label = cellstr(labels);
end

function meta = local_meta_from_atlas(atlas, nearest)
    meta = struct();
    if isfield(atlas, 'roi_name') && ~isempty(atlas.roi_name)
        meta.label = cellstr(string(atlas.roi_name(nearest)));
    elseif isfield(atlas, 'roi_label') && ~isempty(atlas.roi_label)
        meta.label = cellstr(string(atlas.roi_label(nearest)));
    else
        meta.label = cellstr("parcel_" + string(nearest));
    end
    if isfield(atlas, 'hemi') && numel(atlas.hemi) >= max(nearest)
        meta.hemi = atlas.hemi(nearest);
    end
    if isfield(atlas, 'network') && numel(atlas.network) >= max(nearest)
        meta.network = atlas.network(nearest);
    end
    meta.source_index = nearest(:);
end

function out = local_subset_meta(meta, labels)
    out = struct();
    out.label = cellstr(labels(:));
    for f = {'hemi','network'}
        name = f{1};
        if isfield(meta, name)
            vals = string(meta.(name)(:));
            srcLabels = string(meta.label(:));
            out.(name) = cell(numel(labels), 1);
            for i = 1:numel(labels)
                k = find(srcLabels == labels(i), 1);
                if isempty(k), out.(name){i} = ''; else, out.(name){i} = char(vals(k)); end
            end
        end
    end
end
