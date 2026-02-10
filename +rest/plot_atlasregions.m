function fig = plot_atlasregions(params, varargin)
%PLOT_ATLASREGIONS Visualize atlas ROI centroids grouped by network.
%
% Usage:
%   fig = rest.plot_atlasregions(params);
%
% Required params fields:
%   - AtlasPath
% Optional params fields:
%   - HeadModelPath / HeadModel (for plotting a brain mesh when FieldTrip is available)
%   - Unit (default 'mm')
%   - AtlasNetworkOrder (default Schaefer7 order)
%
% Name-value options:
%   'Visible'  : 'on'|'off' (default 'off')
%   'Title'    : char/string (default '')
%   'View'     : [az el] (default [90 0])
%
% Notes:
% - Network parsing follows rest.atlas_load and is compatible with
%   Schaefer2018 "7Networks_*" ROI names used in DISCOVER-EEG.

    ip = inputParser;
    ip.addRequired('params', @isstruct);
    ip.addParameter('Visible', 'off', @(s) ischar(s) || isstring(s));
    ip.addParameter('Title', '', @(s) ischar(s) || isstring(s));
    ip.addParameter('View', [90 0], @(x) isnumeric(x) && numel(x) == 2);
    ip.parse(params, varargin{:});
    R = ip.Results;

    unit = 'mm';
    if isfield(params, 'Unit') && ~isempty(params.Unit)
        unit = char(string(params.Unit));
    end

    atlasPath = '';
    if isfield(params, 'AtlasPath') && ~isempty(params.AtlasPath)
        atlasPath = char(string(params.AtlasPath));
    end
    if isempty(atlasPath)
        error('rest:plot_atlasregions:MissingAtlas', 'params.AtlasPath is required.');
    end

    netOrder = {'Vis','SomMot','DorsAttn','SalVentAttn','Limbic','Cont','Default'};
    if isfield(params, 'AtlasNetworkOrder') && ~isempty(params.AtlasNetworkOrder)
        netOrder = params.AtlasNetworkOrder;
    end

    atlas = rest.atlas_load(atlasPath, 'NetworkOrder', netOrder);

    % Choose networks to show (ordered, then any extras).
    netsPresent = unique(atlas.network, 'stable');
    netsPresent = netsPresent(:);
    netsOrdered = netOrder(:);
    extra = setdiff(netsPresent, netsOrdered, 'stable');
    nets = [netsOrdered; extra];
    keep = false(size(nets));
    for i = 1:numel(nets)
        keep(i) = any(strcmp(atlas.network, nets{i}));
    end
    nets = nets(keep);

    fig = figure('Color', 'w', 'Visible', char(string(R.Visible)));
    ax = axes(fig); %#ok<LAXES>
    hold(ax, 'on');

    % Optional head mesh background.
    if exist('ft_plot_mesh', 'file') == 2
        try
            hm = load_headmodel(params, unit);
            if isstruct(hm) && isfield(hm, 'bnd') && ~isempty(hm.bnd)
                bnd = hm.bnd;
                if numel(bnd) >= 3
                    ft_plot_mesh(bnd(3), 'facealpha', 0.08, 'facecolor', [0.10 0.10 0.10], ...
                        'edgecolor', [1 1 1], 'edgealpha', 0.15);
                else
                    ft_plot_mesh(bnd(end), 'facealpha', 0.08, 'facecolor', [0.10 0.10 0.10], ...
                        'edgecolor', [1 1 1], 'edgealpha', 0.15);
                end
            end
        catch
            % best-effort only
        end
    end

    c = lines(numel(nets));
    h = gobjects(numel(nets), 1);
    for i = 1:numel(nets)
        idx = find(strcmp(atlas.network, nets{i}));
        if isempty(idx), continue; end
        if exist('ft_plot_mesh', 'file') == 2
            ft_plot_mesh(atlas.pos(idx, :), 'vertexsize', 15, 'vertexcolor', c(i, :));
        else
            scatter3(ax, atlas.pos(idx, 1), atlas.pos(idx, 2), atlas.pos(idx, 3), 28, c(i, :), 'filled');
        end
        % Dummy handle for legend (robust across plotting backends)
        h(i) = scatter(ax, NaN, NaN, 28, c(i, :), 'filled'); %#ok<AGROW>
    end

    axis(ax, 'equal');
    axis(ax, 'off');
    view(ax, double(R.View));
    title(ax, char(string(R.Title)), 'Interpreter', 'none');
    legend(ax, h, nets, 'Color', 'none', 'Interpreter', 'none', 'Location', 'eastoutside');

    hold(ax, 'off');
end

