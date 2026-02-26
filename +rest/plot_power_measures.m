function fig = plot_power_measures(res, varargin)
%PLOT_POWER_MEASURES Power-based measures panel: PSD + source power topographies.
%
% This creates a single figure similar to DISCOVER-EEG "Power-based measures":
%   - left: sensor PSD averaged across electrodes (with band shading and APF markers)
%   - right: source-space power per band (surface map when a cortical mesh is available)
%
% Usage:
%   fig = rest.plot_power_measures(res);
%   fig = rest.plot_power_measures(res, 'Visible','on');
%
% Required fields:
%   - res.power (FieldTrip freq struct)
%   - res.params.FreqBand
%   - res.(band).source_pos, res.(band).source_pow
%
% Name-value options:
%   'Visible'          : 'on'|'off' (default 'off')
%   'Title'            : char/string (default 'Power-based measures')
%   'FreqBand'         : struct of bands (defaults to res.params.FreqBand)
%   'SurfaceModelPath' : optional surface mesh path (FieldTrip readable). If
%                        not provided, tries res.params.SurfaceModelPath.
%   'View'             : [az el] (default [0 90], axial)
%
% Notes:
% - When a cortical surface is available (e.g., surface_white_both.mat), ROI
%   power is mapped to the surface using nearest-neighbor interpolation,
%   like DISCOVER-EEG's ft_sourceinterpolate(...,'nearest') plots.
% - Source power uses per-band color scaling (like the DISCOVER-EEG report).
% - For consistent scaling across bands, use rest.plot_power_source with
%   ColorScale='global'.

    ip = inputParser;
    ip.addRequired('res', @isstruct);
    ip.addParameter('Visible', 'off', @(s) ischar(s) || isstring(s));
    ip.addParameter('Title', 'Power-based measures', @(s) ischar(s) || isstring(s));
    ip.addParameter('FreqBand', struct(), @isstruct);
    ip.addParameter('SurfaceModelPath', '', @(s) ischar(s) || isstring(s));
    ip.addParameter('View', [0 90], @(x) isnumeric(x) && numel(x) == 2);
    ip.parse(res, varargin{:});
    R = ip.Results;

    if ~isfield(res, 'power') || ~isstruct(res.power)
        error('rest:plot_power_measures:MissingPower', 'res.power (FieldTrip freq struct) is required.');
    end
    if ~isfield(res, 'params') || ~isstruct(res.params) || ~isfield(res.params, 'FreqBand') || ~isstruct(res.params.FreqBand)
        error('rest:plot_power_measures:MissingBands', 'res.params.FreqBand is required.');
    end

    power = res.power;

    freqBand = R.FreqBand;
    if isempty(fieldnames(freqBand))
        freqBand = res.params.FreqBand;
    end

    % Bands to show on the source topographies.
    allBands = fieldnames(freqBand);
    keepB = false(size(allBands));
    for i = 1:numel(allBands)
        b = allBands{i};
        keepB(i) = isfield(res, b) && isstruct(res.(b)) ...
            && isfield(res.(b), 'source_pos') && isfield(res.(b), 'source_pow') ...
            && ~isempty(res.(b).source_pos) && ~isempty(res.(b).source_pow);
    end
    bandNames = allBands(keepB);
    if isempty(bandNames)
        error('rest:plot_power_measures:NoSourcePower', 'No bands with source_pos+source_pow found.');
    end

    nBand = numel(bandNames);
    [nRowBand, nColBand] = local_grid(nBand);

    % Optional cortical surface mesh (FieldTrip). Prefer EEGflow resources / FieldTrip templates.
    params = struct();
    if isfield(res, 'params') && isstruct(res.params)
        params = res.params;
    end
    [surf, ~] = load_surface(params, R.SurfaceModelPath);
    canSurface = ~isempty(surf) && exist('ft_plot_mesh', 'file') == 2;

    nRow = nRowBand;
    nCol = nColBand + 1; % PSD column + band tiles

    figW = max(16, 4.0 * nCol);
    figH = max(8, 4.0 * nRow);
    fig = figure('Units', 'centimeters', 'Position', [0 0 figW figH], ...
        'Visible', char(string(R.Visible)), 'Color', 'w');
    tcl = tiledlayout(fig, nRow, nCol, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tcl, char(string(R.Title)), 'Interpreter', 'none');

    % --- Left: PSD axis spanning all rows in the first column ---
    % Use TileSpan for compatibility across MATLAB versions.
    axPsd = nexttile(tcl, 1);
    axPsd.Layout.TileSpan = [nRowBand 1];
    hold(axPsd, 'on');

    avgpow = mean(double(power.powspctrm), 1, 'omitnan');
    f = double(power.freq(:).');

    freqNamesShade = fieldnames(freqBand);
    c = lines(numel(freqNamesShade));
    a = gobjects(numel(freqNamesShade), 1);
    for iFreq = 1:numel(freqNamesShade)
        lim = freqBand.(freqNamesShade{iFreq});
        if ~isnumeric(lim) || numel(lim) ~= 2, continue; end
        idx = f >= lim(1) & f <= lim(2);
        if ~any(idx), continue; end
        a(iFreq) = area(axPsd, f(idx), avgpow(idx), ...
            'FaceColor', c(iFreq, :), 'FaceAlpha', 0.30, 'EdgeColor', 'none', ...
            'DisplayName', freqNamesShade{iFreq});
    end
    plot(axPsd, f, avgpow, 'k', 'LineWidth', 1.25, 'DisplayName', 'PSD');

    % Peak frequency markers (if available)
    if isfield(res, 'peakfrequency') && isstruct(res.peakfrequency)
        pf = res.peakfrequency;
        if isfield(pf, 'localmax') && ~isempty(pf.localmax) && isfinite(pf.localmax)
            y = interp1(f, avgpow, double(pf.localmax), 'linear', 'extrap');
            plot(axPsd, double(pf.localmax), y, 'v', 'MarkerSize', 6, ...
                'MarkerEdgeColor', [0.00 0.40 0.20], 'MarkerFaceColor', [0.00 0.40 0.20], ...
                'DisplayName', 'APF - max');
        end
        if isfield(pf, 'cog') && ~isempty(pf.cog) && isfinite(pf.cog)
            y = interp1(f, avgpow, double(pf.cog), 'linear', 'extrap');
            plot(axPsd, double(pf.cog), y, 'v', 'MarkerSize', 6, ...
                'MarkerEdgeColor', [0.60 0.75 0.12], 'MarkerFaceColor', [0.60 0.75 0.12], ...
                'DisplayName', 'APF - c.o.g.');
        end
    end

    title(axPsd, 'Power spectrum (electrode avg.)', 'Interpreter', 'none');
    ylabel(axPsd, 'Power (uV^2/Hz)');
    xlabel(axPsd, 'Frequency (Hz)');
    box(axPsd, 'off');
    grid(axPsd, 'on');
    legend(axPsd, 'show', 'Location', 'eastoutside', 'Color', 'none', 'Interpreter', 'none');
    hold(axPsd, 'off');

    % --- Right: per-band source power ---
    for iB = 1:nBand
        band = bandNames{iB};
        pos = double(res.(band).source_pos);
        pow = double(res.(band).source_pow(:));
        if size(pos, 1) ~= numel(pow)
            continue;
        end

        [r, c2] = local_pos(iB, nColBand);
        globalCol = 1 + c2; % offset by PSD column
        tileIdx = (r-1) * nCol + globalCol;
        ax = nexttile(tcl, tileIdx);

        hold(ax, 'on');

        % Per-band scaling (matches DISCOVER-EEG-style figures).
        vv = pow(isfinite(pow));
        if isempty(vv)
            c = [0 1];
        else
            c = [min(vv) max(vv)];
            if c(2) <= c(1)
                c = c(1) + [-1 1] * max(abs(c(1)), 1);
            end
        end

        didSurface = false;
        if canSurface
            % Map node power onto the surface (nearest) and render a surface map.
            powSurf = interp_to_surface_nearest(surf.pos, pos, pow);
            try
                ft_plot_mesh(surf, 'edgecolor', 'none', 'vertexcolor', 'curv');
                ft_plot_mesh(surf, 'edgecolor', 'none', 'vertexcolor', powSurf, ...
                    'clim', c, 'colormap', parula);
                try, camlight; catch, end %#ok<CTCH>
                didSurface = true;
            catch
                didSurface = false;
            end
        end

        if ~didSurface
            % Fall back to ROI nodes (still colored by power).
            if canSurface
                try
                    ft_plot_mesh(surf, 'edgecolor', 'none', 'vertexcolor', 'curv', 'facealpha', 0.20);
                catch
                end
            end
            scatter3(ax, pos(:, 1), pos(:, 2), pos(:, 3), 24, pow, 'filled', 'MarkerEdgeColor', 'none');
        end

        axis(ax, 'equal');
        axis(ax, 'off');
        view(ax, double(R.View));
        title(ax, band, 'Interpreter', 'none');
        colormap(ax, parula);
        caxis(ax, c);
        colorbar(ax);
        hold(ax, 'off');
    end
end

function [nRow, nCol] = local_grid(n)
    nCol = ceil(sqrt(n));
    nRow = ceil(n / nCol);
end

function [r, c] = local_pos(i, nCol)
    r = floor((i-1) / nCol) + 1;
    c = mod((i-1), nCol) + 1;
end

% (no mesh helper needed; we prefer cortical surface templates when available)
