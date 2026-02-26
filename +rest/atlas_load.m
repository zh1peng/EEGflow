function atlas = atlas_load(atlasPath, varargin)
%ATLAS_LOAD Load an atlas centroid CSV and parse ROI metadata.
%
% Usage:
%   atlas = rest.atlas_load(atlasPath);
%
% Returns a struct:
%   atlas.path      : char
%   atlas.pos       : [n x 3] centroid positions (R/A/S or X/Y/Z)
%   atlas.roi_label : [n x 1] numeric (if present; otherwise [])
%   atlas.roi_name  : {n x 1} cellstr (if present; otherwise {})
%   atlas.hemi      : {n x 1} cellstr ('LH','RH','U')
%   atlas.network   : {n x 1} cellstr (e.g., 'Vis','SomMot',...,'Unknown')
%
% Notes:
% - The default network parsing is compatible with Schaefer2018
%   "7Networks_*" ROI naming (used in DISCOVER-EEG).
%
% This function contains logic derived from DISCOVER-EEG plotting utilities
% (CC BY 4.0). The implementation here is dependency-free.

    ip = inputParser;
    ip.addRequired('atlasPath', @(s) ischar(s) || isstring(s));
    ip.addParameter('NetworkOrder', {'Vis','SomMot','DorsAttn','SalVentAttn','Limbic','Cont','Default'}, ...
        @(x) iscellstr(x) || isstring(x));
    ip.parse(atlasPath, varargin{:});
    R = ip.Results;

    p = char(string(R.atlasPath));
    if exist(p, 'file') ~= 2
        error('rest:atlas_load:NotFound', 'Atlas file not found: %s', p);
    end

    % Preserve column headers to avoid noisy "VariableNames modified" warnings.
    % We normalize names ourselves below for robust matching.
    T = readtable(p, 'VariableNamingRule', 'preserve');
    pos = atlas_table_to_pos(T);

    atlas = struct();
    atlas.path = p;
    atlas.pos = pos;

    % Optional metadata columns (handle common naming variants).
    vars = lower(string(T.Properties.VariableNames));
    % Normalize headers like "ROI Label" -> "roi_label" for matching.
    vars = regexprep(vars, '[^a-z0-9]+', '_');
    vars = regexprep(vars, '^_+|_+$', '');

    atlas.roi_label = [];
    idxLabel = find(vars == "roilabel" | vars == "roi_label" | vars == "label", 1);
    if ~isempty(idxLabel)
        v = T{:, idxLabel};
        if isnumeric(v)
            atlas.roi_label = v(:);
        else
            atlas.roi_label = str2double(string(v(:)));
        end
    end

    atlas.roi_name = {};
    idxName = find(vars == "roiname" | vars == "roi_name" | vars == "name", 1);
    if ~isempty(idxName)
        atlas.roi_name = cellstr(string(T{:, idxName}));
    end

    % Parse hemisphere + network from ROI names when available.
    n = size(pos, 1);
    hemi = repmat({'U'}, n, 1);
    net = repmat({'Unknown'}, n, 1);

    if ~isempty(atlas.roi_name)
        rn = atlas.roi_name;

        isLH = contains(rn, '_LH_') | startsWith(rn, 'LH_') | contains(rn, 'Left', 'IgnoreCase', true);
        isRH = contains(rn, '_RH_') | startsWith(rn, 'RH_') | contains(rn, 'Right', 'IgnoreCase', true);
        hemi(isLH) = {'LH'};
        hemi(isRH) = {'RH'};

        netOrder = R.NetworkOrder;
        if isstring(netOrder), netOrder = cellstr(netOrder); end
        for i = 1:numel(netOrder)
            key = netOrder{i};
            if isempty(key), continue; end
            m = contains(rn, ['_' key '_']);
            net(m) = {key};
        end
    end

    atlas.hemi = hemi;
    atlas.network = net;
end
