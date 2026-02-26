function fig = plot_connectivity(res, connMeasure, varargin)
%PLOT_CONNECTIVITY Plot source-space connectivity matrices (network-blocked).
%
% Usage:
%   fig = rest.plot_connectivity(res, 'dwpli');
%   fig = rest.plot_connectivity(res, 'aec');
%
% Input:
%   res         : output struct from rest.compute_all_features (loaded from MAT)
%   connMeasure : 'dwpli' or 'aec'
%
% Name-value options:
%   'Visible'          : 'on'|'off' (default 'off')
%   'Title'            : char/string (default connMeasure)
%   'ShowNetworkLabels': logical (default true)
%   'ColorScale'       : 'shared'|'perband' (default 'shared')
%
% Notes:
% - If res.(band).parcellation exists, it is used to reorder nodes by
%   functional networks (Schaefer7-style). Otherwise, the matrix is plotted
%   in its native node order.
% - The style is inspired by DISCOVER-EEG (CC BY 4.0).

    ip = inputParser;
    ip.addRequired('res', @isstruct);
    ip.addRequired('connMeasure', @(s) ischar(s) || isstring(s));
    ip.addParameter('Visible', 'off', @(s) ischar(s) || isstring(s));
    ip.addParameter('Title', '', @(s) ischar(s) || isstring(s));
    ip.addParameter('ShowNetworkLabels', true, @(x) islogical(x) && isscalar(x));
    ip.addParameter('ColorScale', 'shared', @(s) ischar(s) || isstring(s));
    ip.parse(res, connMeasure, varargin{:});
    R = ip.Results;

    cm = lower(char(string(R.connMeasure)));
    fieldName = sprintf('%s_connMatrix', cm);

    if ~isfield(res, 'params') || ~isstruct(res.params) || ~isfield(res.params, 'FreqBand')
        error('rest:plot_connectivity:MissingBands', 'res.params.FreqBand is required.');
    end
    bandNames = fieldnames(res.params.FreqBand);

    % Keep only bands that exist and have the requested connectivity.
    has = false(size(bandNames));
    for i = 1:numel(bandNames)
        b = bandNames{i};
        has(i) = isfield(res, b) && isstruct(res.(b)) && isfield(res.(b), fieldName) && ~isempty(res.(b).(fieldName));
    end
    bandNames = bandNames(has);
    if isempty(bandNames)
        error('rest:plot_connectivity:NoData', 'No connectivity matrices found for "%s".', fieldName);
    end

    nBand = numel(bandNames);
    nCol = ceil(sqrt(nBand));
    nRow = ceil(nBand / nCol);

    fig = figure('Units', 'centimeters', 'Position', [0 0 10 8.5], ...
        'Visible', char(string(R.Visible)), 'Color', 'w');
    tcl = tiledlayout(fig, nRow, nCol, 'TileSpacing', 'compact', 'Padding', 'compact');

    ttl = char(string(R.Title));
    if isempty(ttl)
        ttl = cm;
    end
    title(tcl, ttl, 'Interpreter', 'none');

    % Put network labels on the last tile to reduce clutter.
    labelTile = nBand;
    scaleMode = lower(char(string(R.ColorScale)));
    if ~ismember(scaleMode, {'shared','perband'})
        error('rest:plot_connectivity:BadColorScale', 'ColorScale must be shared|perband.');
    end

    cLimShared = [0 1];
    if strcmp(scaleMode, 'shared')
        allV = [];
        for iB = 1:nBand
            b = bandNames{iB};
            C0 = double(res.(b).(fieldName));
            if size(C0, 1) ~= size(C0, 2), continue; end
            v = C0(tril(true(size(C0, 1)), -1));
            allV = [allV; v(:)]; %#ok<AGROW>
        end
        cLimShared = local_range(allV);
    end

    for iB = 1:nBand
        band = bandNames{iB};
        C = double(res.(band).(fieldName));
        if size(C, 1) ~= size(C, 2)
            warning('Skipping %s (%s): connMatrix not square.', band, cm);
            continue;
        end

        parc = [];
        if isfield(res.(band), 'parcellation') && isstruct(res.(band).parcellation)
            parc = res.(band).parcellation;
        end

        order = (1:size(C, 1)).';
        boundary = [];
        labelPos = [];
        netNames = {};
        if isstruct(parc) && isfield(parc, 'order_by_network') && numel(parc.order_by_network) == size(C, 1)
            order = parc.order_by_network(:);
            if isfield(parc, 'boundary_ticks'), boundary = parc.boundary_ticks(:); end
            if isfield(parc, 'label_tick_pos'), labelPos = parc.label_tick_pos(:); end
            if isfield(parc, 'network_names'), netNames = parc.network_names; end
        end

        Cr = C(order, order);
        n = size(Cr, 1);

        ax = nexttile(tcl, iB);
        im = imagesc(ax, Cr);
        axis(ax, 'image');
        set(ax, 'YDir', 'normal');
        colormap(ax, parula);

        % Show only lower triangle (exclude diagonal).
        alpha = zeros(n, n);
        alpha(tril(true(n), -1)) = 1;
        im.AlphaData = alpha;

        if strcmp(scaleMode, 'shared')
            caxis(ax, cLimShared);
        else
            caxis(ax, local_range(Cr(tril(true(n), -1))));
        end

        % Network block boundaries (white lines).
        if ~isempty(boundary) && numel(boundary) >= 3
            hold(ax, 'on');
            for k = 2:(numel(boundary)-1)
                x = boundary(k) - 0.5;
                plot(ax, [x x], [0.5 n+0.5], '-', 'Color', [1 1 1], 'LineWidth', 0.75, 'HandleVisibility', 'off');
                plot(ax, [0.5 n+0.5], [x x], '-', 'Color', [1 1 1], 'LineWidth', 0.75, 'HandleVisibility', 'off');
            end
            hold(ax, 'off');
        end

        % Keep x-axis hidden to avoid clutter on subject-level reports.
        if R.ShowNetworkLabels && iB == labelTile && ~isempty(labelPos) && ~isempty(netNames)
            set(ax, 'XTick', [], 'XTickLabel', [], ...
                'YTick', labelPos, 'YTickLabel', netNames, 'TickLength', [0 0], 'Box', 'off');
        else
            set(ax, 'XTick', [], 'YTick', [], 'TickLength', [0 0], 'Box', 'off');
        end

        if strcmp(scaleMode, 'shared')
            if iB == nBand
                colorbar(ax, 'eastoutside');
            end
        else
            colorbar(ax, 'eastoutside');
        end

        title(ax, band, 'Interpreter', 'none');
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
