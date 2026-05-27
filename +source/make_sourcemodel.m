function [sourcemodel, info] = make_sourcemodel(params)
%MAKE_SOURCEMODEL Build a FieldTrip source model from positions or atlas.

    if nargin < 1 || isempty(params), params = struct(); end
    if exist('ft_prepare_sourcemodel', 'file') ~= 2
        error('source:make_sourcemodel:MissingFieldTrip', 'ft_prepare_sourcemodel is required.');
    end

    unit = char(string(local_get(params, 'Unit', 'mm')));
    coordsys = char(string(local_get(params, 'CoordSys', 'mni')));
    headmodel = source.load_headmodel(params, unit);
    [pos, atlas] = local_resolve_positions(params);

    cfg = [];
    cfg.method = 'basedonpos';
    cfg.sourcemodel.pos = double(pos);
    cfg.unit = unit;
    cfg.headmodel = headmodel;
    sourcemodel = ft_prepare_sourcemodel(cfg);
    if ~isfield(sourcemodel, 'coordsys') || isempty(sourcemodel.coordsys)
        sourcemodel.coordsys = coordsys;
    end

    info = struct();
    info.unit = unit;
    info.coordsys = coordsys;
    info.n_positions = size(pos, 1);
    info.atlas = atlas;
end

function [pos, atlas] = local_resolve_positions(params)
    atlas = [];
    atlasPath = char(string(local_get(params, 'AtlasPath', '')));
    atlasTemplate = char(string(local_get(params, 'AtlasTemplate', '')));
    if isempty(atlasPath) && ~isempty(atlasTemplate)
        atlasPath = source.atlas_default_path(atlasTemplate);
    end
    if ~isempty(atlasPath)
        atlas = source.atlas_load(atlasPath);
        idx = local_get(params, 'SourceIndex', []);
        if ~isempty(idx)
            idx = unique(floor(double(idx(:))), 'stable');
            idx = idx(isfinite(idx) & idx >= 1);
            if isempty(idx)
                error('source:make_sourcemodel:BadSourceIndex', 'SourceIndex did not contain valid indices.');
            end
            atlas.source_index = idx;
            atlas.pos = atlas.pos(idx, :);
            for f = {'roi_label','roi_name','hemi','network'}
                name = f{1};
                if isfield(atlas, name) && numel(atlas.(name)) >= max(idx)
                    atlas.(name) = atlas.(name)(idx);
                end
            end
        end
    end

    if isfield(params, 'SourceModel') && isstruct(params.SourceModel) && isfield(params.SourceModel, 'pos')
        pos = double(params.SourceModel.pos);
    elseif isfield(params, 'SourcePos') && ~isempty(params.SourcePos)
        pos = double(params.SourcePos);
    elseif ~isempty(atlas)
        pos = double(atlas.pos);
    else
        error('source:make_sourcemodel:MissingSourcePos', ...
            'Provide SourceModel, SourcePos, AtlasPath, or AtlasTemplate.');
    end
end

function v = local_get(s, field, default)
    v = default;
    if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
        v = s.(field);
    end
end
