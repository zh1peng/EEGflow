function fig = plot_power_source(res, varargin)
%PLOT_POWER_SOURCE Plot source-space power across bands (surface or nodes).
%
% Usage:
%   fig = rest.plot_power_source(res);
%
% Requires:
%   - res.(band).source_pos [n x 3]
%   - res.(band).source_pow [n x 1] (computed when ComputeSourcePower=true)
%
% Name-value options:
%   'Visible'          : 'on'|'off' (default 'off')
%   'Title'            : char/string (default 'Source power')
%   'SurfaceModelPath' : optional path to a cortical surface mesh (FieldTrip
%                        readable, e.g., surface_white_both.mat)
%   'PlotMode'         : 'auto'|'surface'|'nodes' (default 'auto')
%                        - auto   : surface if available, otherwise nodes
%                        - surface: interpolate node power to surface (nearest)
%                        - nodes  : show ROI nodes only (optionally with glass surface)
%   'ColorScale'       : 'global'|'perband' (default 'global')
%   'MarkerSize'       : scalar (default 24) (only used for PlotMode='nodes')
%   'View'             : [az el] (default [0 90], axial)
%
% Notes:
% - This is a lightweight alternative to ft_sourceinterpolate-based plots.

    ip = inputParser;
    ip.addRequired('res', @isstruct);
    ip.addParameter('Visible', 'off', @(s) ischar(s) || isstring(s));
    ip.addParameter('Title', 'Source power', @(s) ischar(s) || isstring(s));
    ip.addParameter('SurfaceModelPath', '', @(s) ischar(s) || isstring(s));
    ip.addParameter('PlotMode', 'auto', @(s) ischar(s) || isstring(s));
    ip.addParameter('ColorScale', 'global', @(s) ischar(s) || isstring(s));
    ip.addParameter('MarkerSize', 24, @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    ip.addParameter('View', [0 90], @(x) isnumeric(x) && numel(x) == 2);
    ip.parse(res, varargin{:});
    R = ip.Results;

    if ~isfield(res, 'params') || ~isfield(res.params, 'FreqBand')
        error('rest:plot_power_source:MissingBands', 'res.params.FreqBand is required.');
    end
    bandNames = fieldnames(res.params.FreqBand);

    has = false(size(bandNames));
    for i = 1:numel(bandNames)
        b = bandNames{i};
        has(i) = isfield(res, b) && isstruct(res.(b)) ...
            && isfield(res.(b), 'source_pos') && isfield(res.(b), 'source_pow') ...
            && ~isempty(res.(b).source_pos) && ~isempty(res.(b).source_pow);
    end
    bandNames = bandNames(has);
    if isempty(bandNames)
        error('rest:plot_power_source:NoData', 'No bands with source_pos+source_pow found.');
    end

    nBand = numel(bandNames);
    nCol = ceil(sqrt(nBand));
    nRow = ceil(nBand / nCol);

    % Load optional cortical surface mesh (FieldTrip). Prefer EEGflow resources / FieldTrip templates.
    params = struct();
    if isfield(res, 'params') && isstruct(res.params)
        params = res.params;
    end
    [surf, ~] = load_surface(params, R.SurfaceModelPath);
    canSurface = ~isempty(surf) && exist('ft_plot_mesh', 'file') == 2;

    plotMode = lower(char(string(R.PlotMode)));
    if ~ismember(plotMode, {'auto','surface','nodes'})
        error('rest:plot_power_source:BadPlotMode', 'PlotMode must be auto|surface|nodes.');
    end

    colorScale = lower(char(string(R.ColorScale)));
    if ~ismember(colorScale, {'global','perband'})
        error('rest:plot_power_source:BadColorScale', 'ColorScale must be global|perband.');
    end

    cLimGlobal = [0 1];
    if strcmp(colorScale, 'global')
        allPow = [];
        for i = 1:nBand
            b = bandNames{i};
            allPow = [allPow; double(res.(b).source_pow(:))]; %#ok<AGROW>
        end
        allPow = allPow(isfinite(allPow));
        cLimGlobal = local_range(allPow);
    end

    fig = figure('Units', 'centimeters', 'Position', [0 0 10 10], ...
        'Visible', char(string(R.Visible)), 'Color', 'w');
    tcl = tiledlayout(fig, nRow, nCol, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tcl, char(string(R.Title)), 'Interpreter', 'none');

    for i = 1:nBand
        band = bandNames{i};
        pos = double(res.(band).source_pos);
        pow = double(res.(band).source_pow(:));
        if size(pos, 1) ~= numel(pow)
            warning('Skipping %s: source_pos rows do not match source_pow length.', band);
            continue;
        end

        ax = nexttile(tcl, i);
        hold(ax, 'on');

        doSurface = false;
        switch plotMode
            case 'auto'
                doSurface = canSurface;
            case 'surface'
                doSurface = canSurface;
            case 'nodes'
                doSurface = false;
        end

        cLim = cLimGlobal;
        if strcmp(colorScale, 'perband')
            cLim = local_range(pow);
        end

        if doSurface
            % Map node values to the surface (nearest neighbor) and render a surface map.
            powSurf = interp_to_surface_nearest(surf.pos, pos, pow);
            try
                ft_plot_mesh(surf, 'edgecolor', 'none', 'vertexcolor', 'curv');
                ft_plot_mesh(surf, 'edgecolor', 'none', 'vertexcolor', powSurf, ...
                    'clim', cLim, 'colormap', parula);
                try, camlight; catch, end %#ok<CTCH>
            catch
                % If surface rendering fails for any reason, fall back to nodes.
                doSurface = false;
            end
        end

        if ~doSurface
            % Glass brain background + colored nodes.
            if canSurface
                try
                    ft_plot_mesh(surf, 'edgecolor', 'none', 'vertexcolor', 'curv', 'facealpha', 0.20);
                catch
                end
            end

            scatter3(ax, pos(:, 1), pos(:, 2), pos(:, 3), double(R.MarkerSize), pow, 'filled', ...
                'MarkerEdgeColor', 'none');
        end

        axis(ax, 'equal');
        axis(ax, 'off');
        view(ax, double(R.View));
        title(ax, band, 'Interpreter', 'none');
        colormap(ax, parula);
        caxis(ax, cLim);
        colorbar(ax);
        hold(ax, 'off');
    end
end

function c = local_range(v)
    v = double(v(:));
    v = v(isfinite(v));
    if isempty(v)
        c = [0 1];
        return;
    end
    c = [min(v) max(v)];
    if c(2) <= c(1)
        c = c(1) + [-1 1] * max(abs(c(1)), 1);
    end
end
