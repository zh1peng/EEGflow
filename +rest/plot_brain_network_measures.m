function fig = plot_brain_network_measures(res, varargin)
%PLOT_BRAIN_NETWORK_MEASURES Local graph measures panel across bands.
%
% This creates a "Brain network measures"-style figure showing local
% (nodal) graph metrics across frequency bands for one or more
% connectivity measures (dwPLI, AEC).
%
% Default behavior:
%   - measure: dwPLI
%   - metric : nodal degree (adeg)
%   - rendering: ROI nodes on glass brain (no surface interpolation)
%
% Usage:
%   fig = rest.plot_brain_network_measures(res);
%   fig = rest.plot_brain_network_measures(res, 'Visible','on', 'View',[0 90]);
%
% Required fields:
%   - res.params.FreqBand
%   - res.(band).source_pos
%   - res.(band).<measure>_node_sum.<metric>
%
% Name-value options:
%   'Measures'         : cellstr/string array (default {'dwpli'})
%   'NodeMetrics'      : cellstr/string array (default {'adeg'})
%   'Visible'          : 'on'|'off' (default 'off')
%   'Title'            : char/string (default 'Brain network measures')
%   'SurfaceModelPath' : optional surface mesh (FieldTrip readable). If not
%                        provided, tries res.params.SurfaceModelPath.
%   'View'             : [az el] (default [0 90], axial)
%   'MarkerSize'       : scalar (default 24)
%
% Notes:
% - Color scaling is consistent across bands within each (measure, metric)
%   group, and the colorbar is shown only on the last band tile.

    ip = inputParser;
    ip.addRequired('res', @isstruct);
    ip.addParameter('Measures', {'dwpli'}, @(x) iscellstr(x) || isstring(x));
    ip.addParameter('NodeMetrics', {'adeg'}, @(x) iscellstr(x) || isstring(x));
    ip.addParameter('Visible', 'off', @(s) ischar(s) || isstring(s));
    ip.addParameter('Title', 'Brain network measures', @(s) ischar(s) || isstring(s));
    ip.addParameter('SurfaceModelPath', '', @(s) ischar(s) || isstring(s));
    ip.addParameter('View', [0 90], @(x) isnumeric(x) && numel(x) == 2);
    ip.addParameter('MarkerSize', 24, @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    ip.parse(res, varargin{:});
    R = ip.Results;

    if ~isfield(res, 'params') || ~isstruct(res.params) || ~isfield(res.params, 'FreqBand') || ~isstruct(res.params.FreqBand)
        error('rest:plot_brain_network_measures:MissingBands', 'res.params.FreqBand is required.');
    end

    measures = R.Measures;
    if isstring(measures), measures = cellstr(measures); end
    measures = cellfun(@(s) lower(char(string(s))), measures, 'UniformOutput', false);
    measures = measures(:).';

    nodeMetrics = R.NodeMetrics;
    if isstring(nodeMetrics), nodeMetrics = cellstr(nodeMetrics); end
    nodeMetrics = cellfun(@(s) char(string(s)), nodeMetrics, 'UniformOutput', false);
    nodeMetrics = nodeMetrics(:).';
    if isempty(nodeMetrics)
        error('rest:plot_brain_network_measures:BadInput', 'NodeMetrics must be non-empty.');
    end
    if numel(nodeMetrics) > 2
        nodeMetrics = nodeMetrics(1:2);
    end

    allBands = fieldnames(res.params.FreqBand);
    if isempty(allBands)
        error('rest:plot_brain_network_measures:NoBands', 'res.params.FreqBand is empty.');
    end

    % Keep measures that have at least one band with graph outputs.
    keepM = false(size(measures));
    for iM = 1:numel(measures)
        nodeField = sprintf('%s_node_sum', measures{iM});
        for iB = 1:numel(allBands)
            b = allBands{iB};
            if isfield(res, b) && isstruct(res.(b)) ...
                    && isfield(res.(b), 'source_pos') && ~isempty(res.(b).source_pos) ...
                    && isfield(res.(b), nodeField) && isstruct(res.(b).(nodeField))
                S = res.(b).(nodeField);
                if isfield(S, nodeMetrics{1}) && ~isempty(S.(nodeMetrics{1}))
                    keepM(iM) = true;
                    break;
                end
            end
        end
    end
    measures = measures(keepM);
    if isempty(measures)
        error('rest:plot_brain_network_measures:NoData', 'No graph measures found. (Did you run ComputeGraph with GRETNA?)');
    end

    % Keep only bands that have all requested measures + metrics.
    keepB = false(size(allBands));
    for iB = 1:numel(allBands)
        b = allBands{iB};
        ok = isfield(res, b) && isstruct(res.(b)) && isfield(res.(b), 'source_pos') && ~isempty(res.(b).source_pos);
        if ~ok
            keepB(iB) = false;
            continue;
        end

        for iM = 1:numel(measures)
            nodeField = sprintf('%s_node_sum', measures{iM});
            ok = ok && isfield(res.(b), nodeField) && isstruct(res.(b).(nodeField));
            if ~ok, break; end

            S = res.(b).(nodeField);
            for iK = 1:numel(nodeMetrics)
                ok = ok && isfield(S, nodeMetrics{iK}) && ~isempty(S.(nodeMetrics{iK}));
            end
            if ~ok, break; end
        end
        keepB(iB) = ok;
    end
    bandNames = allBands(keepB);
    if isempty(bandNames)
        error('rest:plot_brain_network_measures:NoBandsWithData', 'No bands found with graph measures for all requested measures/metrics.');
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

    nMeasure = numel(measures);
    nMetric = numel(nodeMetrics);
    nRow = nRowBand;
    nCol = nColBand * nMetric * nMeasure;

    figW = max(14, 3.2 * nCol);
    figH = max(8, 3.8 * nRow);
    fig = figure('Units', 'centimeters', 'Position', [0 0 figW figH], ...
        'Visible', char(string(R.Visible)), 'Color', 'w');
    tcl = tiledlayout(fig, nRow, nCol, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tcl, char(string(R.Title)), 'Interpreter', 'none');

    % Group headings (only when needed to keep compact layout).
    if nMeasure > 1 || nMetric > 1
        for iM = 1:nMeasure
            x = ((iM-1) * nMetric * nColBand) / nCol;
            w = (nMetric * nColBand) / nCol;
            annotation(fig, 'textbox', [x 0.955 w 0.035], ...
                'String', local_measure_title(measures{iM}), ...
                'EdgeColor', 'none', 'HorizontalAlignment', 'center', ...
                'Interpreter', 'none', 'FontWeight', 'bold');

            for iK = 1:nMetric
                x2 = ((iM-1) * nMetric * nColBand + (iK-1) * nColBand) / nCol;
                w2 = nColBand / nCol;
                annotation(fig, 'textbox', [x2 0.925 w2 0.030], ...
                    'String', local_metric_title(nodeMetrics{iK}), ...
                    'EdgeColor', 'none', 'HorizontalAlignment', 'center', ...
                    'Interpreter', 'none');
            end
        end
    end

    % Pre-compute color limits per (measure, metric) across all bands.
    cLim = cell(nMeasure, nMetric);
    for iM = 1:nMeasure
        nodeField = sprintf('%s_node_sum', measures{iM});
        for iK = 1:nMetric
            metric = nodeMetrics{iK};
            allV = [];
            for iB = 1:nBand
                b = bandNames{iB};
                S = res.(b).(nodeField);
                v = double(S.(metric)(:));
                allV = [allV; v]; %#ok<AGROW>
            end
            allV = allV(isfinite(allV));
            if isempty(allV)
                cLim{iM, iK} = [0 1];
            else
                c = [min(allV) max(allV)];
                if c(2) <= c(1)
                    c = c(1) + [-1 1] * max(abs(c(1)), 1);
                end
                cLim{iM, iK} = c;
            end
        end
    end

    for iM = 1:nMeasure
        nodeField = sprintf('%s_node_sum', measures{iM});
        for iK = 1:nMetric
            metric = nodeMetrics{iK};

            for iB = 1:nBand
                b = bandNames{iB};
                pos = double(res.(b).source_pos);
                v = double(res.(b).(nodeField).(metric)(:));
                if size(pos, 1) ~= numel(v)
                    continue;
                end

                [r, c] = local_pos(iB, nColBand);
                groupColStart = (iM-1) * nMetric * nColBand + (iK-1) * nColBand;
                globalCol = groupColStart + c;
                tileIdx = (r-1) * nCol + globalCol;

                ax = nexttile(tcl, tileIdx);
                hold(ax, 'on');
                if canSurface
                    try
                        ft_plot_mesh(surf, 'edgecolor', 'none', 'vertexcolor', 'curv', 'facealpha', 0.20);
                    catch
                    end
                end
                scatter3(ax, pos(:, 1), pos(:, 2), pos(:, 3), double(R.MarkerSize), v, ...
                    'filled', 'MarkerEdgeColor', 'none');

                colormap(ax, parula);
                caxis(ax, cLim{iM, iK});

                axis(ax, 'equal');
                axis(ax, 'off');
                view(ax, double(R.View));
                title(ax, b, 'Interpreter', 'none');

                % Colorbar only on the last band tile (per group).
                if iB == nBand
                    colorbar(ax, 'eastoutside');
                end

                hold(ax, 'off');
            end
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

function ttl = local_measure_title(m)
    m = lower(char(string(m)));
    switch m
        case 'dwpli'
            ttl = 'Local graph measures (dwPLI)';
        case 'aec'
            ttl = 'Local graph measures (AEC)';
        otherwise
            ttl = sprintf('Local graph measures (%s)', upper(m));
    end
end

function ttl = local_metric_title(metric)
    metric = char(string(metric));
    switch lower(metric)
        case 'adeg'
            ttl = 'Degree';
        case lower('aCp')
            ttl = 'Clustering coef.';
        otherwise
            ttl = metric;
    end
end
