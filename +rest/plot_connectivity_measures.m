function fig = plot_connectivity_measures(res, varargin)
%PLOT_CONNECTIVITY_MEASURES Plot connectivity panels across bands.
%
% This produces a figure with connectivity matrices arranged as:
%   [measure1 bands ... | measure2 bands ...]
%
% Usage:
%   fig = rest.plot_connectivity_measures(res);
%   fig = rest.plot_connectivity_measures(res, 'Visible','on');
%   fig = rest.plot_connectivity_measures(res, 'Measures', {'dwpli'});
%
% Input:
%   res : output struct from rest.compute_all_features (loaded from MAT)
%
% Name-value options:
%   'Measures'         : cellstr/string array (default {'dwpli'})
%   'Visible'          : 'on'|'off' (default 'off')
%   'Title'            : char/string (default 'Functional connectivity measures')
%   'ShowNetworkLabels': logical (default true)
%   'ColorScale'       : 'shared'|'perband' (default 'shared')
%
% Notes:
% - Bands are determined from res.params.FreqBand and filtered to those that
%   contain connectivity matrices for all requested measures.
% - If parcellation metadata exists (res.(band).parcellation), nodes are
%   reordered by functional network and boundaries are drawn.

    ip = inputParser;
    ip.addRequired('res', @isstruct);
    ip.addParameter('Measures', {'dwpli'}, @(x) iscellstr(x) || isstring(x));
    ip.addParameter('Visible', 'off', @(s) ischar(s) || isstring(s));
    ip.addParameter('Title', 'Functional connectivity measures', @(s) ischar(s) || isstring(s));
    ip.addParameter('ShowNetworkLabels', true, @(x) islogical(x) && isscalar(x));
    ip.addParameter('ColorScale', 'shared', @(s) ischar(s) || isstring(s));
    ip.parse(res, varargin{:});
    R = ip.Results;

    if ~isfield(res, 'params') || ~isstruct(res.params) || ~isfield(res.params, 'FreqBand') || ~isstruct(res.params.FreqBand)
        error('rest:plot_connectivity_measures:MissingBands', 'res.params.FreqBand is required.');
    end

    measures = R.Measures;
    if isstring(measures), measures = cellstr(measures); end
    measures = cellfun(@(s) lower(char(string(s))), measures, 'UniformOutput', false);
    measures = measures(:).';

    allBands = fieldnames(res.params.FreqBand);
    if isempty(allBands)
        error('rest:plot_connectivity_measures:NoBands', 'res.params.FreqBand is empty.');
    end

    % Keep only requested measures that have at least one matrix.
    keepM = false(size(measures));
    for iM = 1:numel(measures)
        fieldName = sprintf('%s_connMatrix', measures{iM});
        for iB = 1:numel(allBands)
            b = allBands{iB};
            if isfield(res, b) && isstruct(res.(b)) && isfield(res.(b), fieldName) && ~isempty(res.(b).(fieldName))
                keepM(iM) = true;
                break;
            end
        end
    end
    measures = measures(keepM);
    if isempty(measures)
        error('rest:plot_connectivity_measures:NoData', 'No connectivity matrices found for requested measures.');
    end

    % Keep only bands that have matrices for all measures.
    keepB = false(size(allBands));
    for iB = 1:numel(allBands)
        b = allBands{iB};
        ok = true;
        for iM = 1:numel(measures)
            fieldName = sprintf('%s_connMatrix', measures{iM});
            ok = ok && isfield(res, b) && isstruct(res.(b)) && isfield(res.(b), fieldName) && ~isempty(res.(b).(fieldName));
        end
        keepB(iB) = ok;
    end
    bandNames = allBands(keepB);
    if isempty(bandNames)
        error('rest:plot_connectivity_measures:NoBandsWithData', 'No bands found with connectivity for all requested measures.');
    end

    nBand = numel(bandNames);
    [nRowBand, nColBand] = local_grid(nBand);

    nMeasure = numel(measures);
    nRow = nRowBand;
    nCol = nColBand * nMeasure;
    scaleMode = lower(char(string(R.ColorScale)));
    if ~ismember(scaleMode, {'shared','perband'})
        error('rest:plot_connectivity_measures:BadColorScale', 'ColorScale must be shared|perband.');
    end

    figW = max(12, 3.8 * nCol);
    figH = max(8, 3.6 * nRow);
    fig = figure('Units', 'centimeters', 'Position', [0 0 figW figH], ...
        'Visible', char(string(R.Visible)), 'Color', 'w');
    tcl = tiledlayout(fig, nRow, nCol, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tcl, char(string(R.Title)), 'Interpreter', 'none');

    % Group labels only when there are multiple measures to reduce clutter.
    if nMeasure > 1
        for iM = 1:nMeasure
            x = ((iM-1) * nColBand) / nCol;
            w = nColBand / nCol;
            annotation(fig, 'textbox', [x 0.955 w 0.035], ...
                'String', local_measure_title(measures{iM}), ...
                'EdgeColor', 'none', 'HorizontalAlignment', 'center', ...
                'Interpreter', 'none', 'FontWeight', 'bold');
        end
    end

    labelBandIdx = local_label_band_idx(nBand, nRowBand, nColBand);
    cLimMeasure = cell(1, nMeasure);

    for iM = 1:nMeasure
        cm = measures{iM};
        fieldName = sprintf('%s_connMatrix', cm);

        if strcmp(scaleMode, 'shared')
            allV = [];
            for iB2 = 1:nBand
                b2 = bandNames{iB2};
                C0 = double(res.(b2).(fieldName));
                if size(C0, 1) ~= size(C0, 2), continue; end
                v0 = C0(tril(true(size(C0, 1)), -1));
                allV = [allV; v0(:)]; %#ok<AGROW>
            end
            cLimMeasure{iM} = local_range(allV);
        else
            cLimMeasure{iM} = [0 1]; % placeholder
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

            [r, c] = local_pos(iB, nColBand);
            globalCol = (iM-1) * nColBand + c;
            tileIdx = (r-1) * nCol + globalCol;

            ax = nexttile(tcl, tileIdx);
            im = imagesc(ax, Cr);
            axis(ax, 'image');
            set(ax, 'YDir', 'normal');
            colormap(ax, parula);

            % Show only lower triangle (exclude diagonal).
            alpha = zeros(n, n);
            alpha(tril(true(n), -1)) = 1;
            im.AlphaData = alpha;

            if strcmp(scaleMode, 'shared')
                caxis(ax, cLimMeasure{iM});
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
            if R.ShowNetworkLabels && iB == labelBandIdx && ~isempty(labelPos) && ~isempty(netNames)
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
end

function [nRow, nCol] = local_grid(n)
    nCol = ceil(sqrt(n));
    nRow = ceil(n / nCol);
end

function [r, c] = local_pos(i, nCol)
    r = floor((i-1) / nCol) + 1;
    c = mod((i-1), nCol) + 1;
end

function idx = local_label_band_idx(nBand, nRowBand, nColBand)
    if nRowBand <= 1
        idx = 1;
    else
        % Bottom-left tile tends to leave the bottom-right less cluttered.
        idx = min(nBand, (nRowBand-1) * nColBand + 1);
    end
end

function ttl = local_measure_title(m)
    m = lower(char(string(m)));
    switch m
        case 'dwpli'
            ttl = 'Phase-based connectivity (dwPLI)';
        case 'aec'
            ttl = 'Amplitude-based connectivity (AEC)';
        otherwise
            ttl = upper(m);
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
