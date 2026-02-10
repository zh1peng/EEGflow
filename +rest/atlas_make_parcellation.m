function parc = atlas_make_parcellation(atlas, idxInAtlas, varargin)
%ATLAS_MAKE_PARCELLATION Build a parcellation struct for plotting/reordering.
%
% Usage:
%   parc = rest.atlas_make_parcellation(atlas, idxInAtlas);
%   parc = rest.atlas_make_parcellation(atlas, idxInAtlas, 'Pos', posInside);
%
% Inputs:
%   atlas      : output of rest.atlas_load (or [] for unlabeled nodes)
%   idxInAtlas : indices (into atlas arrays) that correspond to the nodes used
%                in connectivity/graph metrics (e.g., find(source.inside)).
%
% Name-value options:
%   'Pos'          : [n x 3] positions for the nodes in *the same order* as
%                    idxInAtlas. When empty, atlas.pos(idxInAtlas,:) is used.
%   'NetworkOrder' : cellstr ordering for network grouping.
%
% Output:
%   parc : struct with fields:
%     .idx_in_atlas         [n x 1]
%     .pos                  [n x 3]
%     .roi_name             {n x 1}
%     .network              {n x 1}
%     .hemi                 {n x 1}
%     .network_names        {k x 1}
%     .network_idx          {k x 1} cell of indices into 1..n
%     .order_by_network     [n x 1] reorder indices into 1..n
%     .boundary_ticks       [k+1 x 1] boundaries (1-based, for imagesc axes)
%     .label_tick_pos       [k x 1] midpoints for labeling
%
% Notes:
% - Designed to reproduce the "network-block" ordering used in DISCOVER-EEG
%   connectivity plots, without requiring any DISCOVER-EEG code at runtime.

    ip = inputParser;
    ip.addRequired('atlas', @(x) isempty(x) || isstruct(x));
    ip.addRequired('idxInAtlas', @(x) isnumeric(x) && isvector(x));
    ip.addParameter('Pos', [], @(x) isempty(x) || (isnumeric(x) && size(x, 2) == 3));
    ip.addParameter('NetworkOrder', {'Vis','SomMot','DorsAttn','SalVentAttn','Limbic','Cont','Default'}, ...
        @(x) iscellstr(x) || isstring(x));
    ip.parse(atlas, idxInAtlas, varargin{:});
    R = ip.Results;

    idx = R.idxInAtlas(:);
    idx = idx(isfinite(idx) & idx >= 1);
    idx = unique(floor(idx), 'stable');

    n = numel(idx);
    parc = struct();
    parc.idx_in_atlas = idx;

    % Positions
    if ~isempty(R.Pos)
        pos = double(R.Pos);
        if size(pos, 1) ~= n
            error('rest:atlas_make_parcellation:BadPos', 'Pos must have n rows to match idxInAtlas.');
        end
    elseif ~isempty(atlas) && isfield(atlas, 'pos') && ~isempty(atlas.pos)
        pos = double(atlas.pos(idx, :));
    else
        pos = nan(n, 3);
    end
    parc.pos = pos;

    % Names / hemi / network (best-effort)
    roiName = cell(n, 1);
    hemi = repmat({'U'}, n, 1);
    net = repmat({'Unknown'}, n, 1);
    if ~isempty(atlas)
        if isfield(atlas, 'roi_name') && ~isempty(atlas.roi_name)
            rnAll = atlas.roi_name;
            if numel(rnAll) >= max(idx)
                roiName = rnAll(idx);
            end
        end
        if isfield(atlas, 'hemi') && ~isempty(atlas.hemi) && numel(atlas.hemi) >= max(idx)
            hemi = atlas.hemi(idx);
        end
        if isfield(atlas, 'network') && ~isempty(atlas.network) && numel(atlas.network) >= max(idx)
            net = atlas.network(idx);
        end
    end
    if all(cellfun(@isempty, roiName))
        roiName = arrayfun(@(i) sprintf('ROI%03d', i), (1:n)', 'UniformOutput', false);
    end
    parc.roi_name = roiName(:);
    parc.hemi = hemi(:);
    parc.network = net(:);

    % Build network grouping in canonical order.
    netOrder = R.NetworkOrder;
    if isstring(netOrder), netOrder = cellstr(netOrder); end

    netsPresent = unique(parc.network, 'stable');
    netsPresent = netsPresent(:);
    netsOrdered = netOrder(:);
    % Append any networks not in the default list (e.g., 'Unknown') at the end.
    extra = setdiff(netsPresent, netsOrdered, 'stable');
    netNames = [netsOrdered; extra];
    % Keep only those that actually exist in this parcellation.
    keep = false(size(netNames));
    for i = 1:numel(netNames)
        keep(i) = any(strcmp(parc.network, netNames{i}));
    end
    netNames = netNames(keep);

    netIdx = cell(numel(netNames), 1);
    for i = 1:numel(netNames)
        netIdx{i} = find(strcmp(parc.network, netNames{i}));
    end
    order = vertcat(netIdx{:});

    % Boundary ticks and label positions for imagesc.
    lengths = cellfun(@numel, netIdx);
    boundary = [1; 1 + cumsum(lengths(:))];
    labelPos = boundary(1:end-1) + lengths(:) / 2;

    parc.network_names = netNames;
    parc.network_idx = netIdx;
    parc.order_by_network = order;
    parc.boundary_ticks = boundary;
    parc.label_tick_pos = labelPos;
end

