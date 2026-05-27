function parc = atlas_make_parcellation(atlas, idxInAtlas, varargin)
%ATLAS_MAKE_PARCELLATION Build parcel metadata for source/rest outputs.

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
    maxIdx = 0;
    if ~isempty(idx)
        maxIdx = max(idx);
    end
    if ~isempty(R.Pos)
        parc.pos = double(R.Pos);
    elseif ~isempty(atlas) && isfield(atlas, 'pos') && ~isempty(atlas.pos)
        parc.pos = double(atlas.pos(idx, :));
    else
        parc.pos = nan(n, 3);
    end
    if size(parc.pos, 1) ~= n
        error('source:atlas_make_parcellation:BadPos', 'Pos must match idxInAtlas length.');
    end

    parc.roi_name = arrayfun(@(i) sprintf('ROI%03d', i), (1:n)', 'UniformOutput', false);
    parc.hemi = repmat({'U'}, n, 1);
    parc.network = repmat({'Unknown'}, n, 1);
    if ~isempty(atlas)
        if maxIdx > 0 && isfield(atlas, 'roi_name') && numel(atlas.roi_name) >= maxIdx
            parc.roi_name = atlas.roi_name(idx);
        end
        if maxIdx > 0 && isfield(atlas, 'hemi') && numel(atlas.hemi) >= maxIdx
            parc.hemi = atlas.hemi(idx);
        end
        if maxIdx > 0 && isfield(atlas, 'network') && numel(atlas.network) >= maxIdx
            parc.network = atlas.network(idx);
        end
    end

    netOrder = R.NetworkOrder;
    if isstring(netOrder), netOrder = cellstr(netOrder); end
    present = unique(parc.network, 'stable');
    netNames = [netOrder(:); setdiff(present(:), netOrder(:), 'stable')];
    keep = false(numel(netNames), 1);
    for i = 1:numel(netNames)
        keep(i) = any(strcmp(parc.network, netNames{i}));
    end
    netNames = netNames(keep);

    netIdx = cell(numel(netNames), 1);
    for i = 1:numel(netNames)
        netIdx{i} = find(strcmp(parc.network, netNames{i}));
    end
    if isempty(netIdx)
        order = [];
        lengths = [];
    else
        order = vertcat(netIdx{:});
        lengths = cellfun(@numel, netIdx);
    end

    parc.network_names = netNames;
    parc.network_idx = netIdx;
    parc.order_by_network = order;
    parc.boundary_ticks = [1; 1 + cumsum(lengths(:))];
    parc.label_tick_pos = parc.boundary_ticks(1:end-1) + lengths(:) / 2;
end
