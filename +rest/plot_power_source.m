function fig = plot_power_source(res, varargin)
%PLOT_POWER_SOURCE Plot per-ROI source power (colored nodes) across bands.
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
%   'View'             : [az el] (default [90 0])
%
% Notes:
% - This is a lightweight alternative to ft_sourceinterpolate-based plots.

    ip = inputParser;
    ip.addRequired('res', @isstruct);
    ip.addParameter('Visible', 'off', @(s) ischar(s) || isstring(s));
    ip.addParameter('Title', 'Source power', @(s) ischar(s) || isstring(s));
    ip.addParameter('SurfaceModelPath', '', @(s) ischar(s) || isstring(s));
    ip.addParameter('View', [90 0], @(x) isnumeric(x) && numel(x) == 2);
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

    % Load optional surface mesh (FieldTrip).
    surf = [];
    surfPath = char(string(R.SurfaceModelPath));
    if isempty(surfPath) && isfield(res, 'params') && isfield(res.params, 'SurfaceModelPath')
        surfPath = char(string(res.params.SurfaceModelPath));
    end
    if ~isempty(surfPath) && exist('ft_read_headshape', 'file') == 2
        try
            surf = ft_read_headshape(surfPath);
        catch
            surf = [];
        end
    end

    % Global color scaling across all bands.
    allPow = [];
    for i = 1:nBand
        b = bandNames{i};
        allPow = [allPow; double(res.(b).source_pow(:))]; %#ok<AGROW>
    end
    allPow = allPow(isfinite(allPow));
    if isempty(allPow)
        cLim = [0 1];
    else
        cLim = [min(allPow) max(allPow)];
        if cLim(2) <= cLim(1)
            cLim = cLim(1) + [-1 1] * max(abs(cLim(1)), 1);
        end
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
        if ~isempty(surf) && exist('ft_plot_mesh', 'file') == 2
            try
                ft_plot_mesh(surf, 'edgecolor', 'none', 'vertexcolor', 'curv', 'facealpha', 0.10);
            catch
            end
        end

        scatter3(ax, pos(:, 1), pos(:, 2), pos(:, 3), 24, pow, 'filled', ...
            'MarkerEdgeColor', 'none');
        colormap(ax, parula);
        caxis(ax, cLim);
        colorbar(ax);

        axis(ax, 'equal');
        axis(ax, 'off');
        view(ax, double(R.View));
        title(ax, band, 'Interpreter', 'none');
        hold(ax, 'off');
    end
end

