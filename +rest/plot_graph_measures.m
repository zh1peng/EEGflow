function [f_node1, f_node2, f_global] = plot_graph_measures(res, connMeasure, varargin)
%PLOT_GRAPH_MEASURES Plot nodal + global graph measures across bands.
%
% Usage:
%   [fDeg, fCc, fGlobal] = rest.plot_graph_measures(res, 'dwpli');
%
% Input:
%   res         : output struct from rest.compute_all_features
%   connMeasure : 'dwpli' or 'aec'
%
% Name-value options:
%   'NodeMetrics'     : cellstr (default {'adeg','aCp'})
%   'GlobalMetrics'   : cellstr (default {'aCp','agE','amod'})
%   'SurfaceModelPath': optional surface mesh path (FieldTrip readable)
%   'Visible'         : 'on'|'off' (default 'off')
%   'View'            : [az el] (default [90 0])
%
% Notes:
% - This expects GRETNA-style outputs:
%     res.(band).<cm>_node_sum.<metric> : [nNode x 1]
%     res.(band).<cm>_net_sum.<metric>  : scalar
% - The default metrics are chosen to roughly match "degree" and "clustering"
%   style plots from DISCOVER-EEG, but the exact definitions follow GRETNA.

    ip = inputParser;
    ip.addRequired('res', @isstruct);
    ip.addRequired('connMeasure', @(s) ischar(s) || isstring(s));
    ip.addParameter('NodeMetrics', {'adeg','aCp'}, @(x) iscellstr(x) || isstring(x));
    ip.addParameter('GlobalMetrics', {'aCp','agE','amod'}, @(x) iscellstr(x) || isstring(x));
    ip.addParameter('SurfaceModelPath', '', @(s) ischar(s) || isstring(s));
    ip.addParameter('Visible', 'off', @(s) ischar(s) || isstring(s));
    ip.addParameter('View', [90 0], @(x) isnumeric(x) && numel(x) == 2);
    ip.parse(res, connMeasure, varargin{:});
    R = ip.Results;

    cm = lower(char(string(R.connMeasure)));
    nodeField = sprintf('%s_node_sum', cm);
    netField = sprintf('%s_net_sum', cm);

    if ~isfield(res, 'params') || ~isfield(res.params, 'FreqBand')
        error('rest:plot_graph_measures:MissingBands', 'res.params.FreqBand is required.');
    end
    bandNames = fieldnames(res.params.FreqBand);

    has = false(size(bandNames));
    for i = 1:numel(bandNames)
        b = bandNames{i};
        has(i) = isfield(res, b) && isstruct(res.(b)) ...
            && isfield(res.(b), nodeField) && isstruct(res.(b).(nodeField)) ...
            && isfield(res.(b), 'source_pos') && ~isempty(res.(b).source_pos);
    end
    bandNames = bandNames(has);
    if isempty(bandNames)
        error('rest:plot_graph_measures:NoData', 'No bands with %s + source_pos found.', nodeField);
    end

    nBand = numel(bandNames);
    nCol = ceil(sqrt(nBand));
    nRow = ceil(nBand / nCol);

    % Optional surface mesh.
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

    nodeMetrics = R.NodeMetrics;
    if isstring(nodeMetrics), nodeMetrics = cellstr(nodeMetrics); end
    globalMetrics = R.GlobalMetrics;
    if isstring(globalMetrics), globalMetrics = cellstr(globalMetrics); end

    f_node1 = [];
    f_node2 = [];

    % Plot first two nodal metrics if available.
    for iM = 1:min(2, numel(nodeMetrics))
        metric = nodeMetrics{iM};

        % Collect values for color scaling.
        allV = [];
        for iB = 1:nBand
            b = bandNames{iB};
            S = res.(b).(nodeField);
            if isfield(S, metric)
                v = double(S.(metric)(:));
                allV = [allV; v]; %#ok<AGROW>
            end
        end
        allV = allV(isfinite(allV));
        if isempty(allV)
            continue;
        end
        cLim = [min(allV) max(allV)];
        if cLim(2) <= cLim(1)
            cLim = cLim(1) + [-1 1] * max(abs(cLim(1)), 1);
        end

        fig = figure('Units', 'centimeters', 'Position', [0 0 10 9], ...
            'Visible', char(string(R.Visible)), 'Color', 'w');
        tcl = tiledlayout(fig, nRow, nCol, 'TileSpacing', 'compact', 'Padding', 'compact');
        title(tcl, sprintf('%s | %s', cm, metric), 'Interpreter', 'none');

        for iB = 1:nBand
            b = bandNames{iB};
            pos = double(res.(b).source_pos);
            S = res.(b).(nodeField);
            if ~isfield(S, metric)
                continue;
            end
            v = double(S.(metric)(:));
            if size(pos, 1) ~= numel(v)
                continue;
            end

            ax = nexttile(tcl, iB);
            hold(ax, 'on');
            if ~isempty(surf) && exist('ft_plot_mesh', 'file') == 2
                try
                    ft_plot_mesh(surf, 'edgecolor', 'none', 'vertexcolor', 'curv', 'facealpha', 0.10);
                catch
                end
            end

            scatter3(ax, pos(:, 1), pos(:, 2), pos(:, 3), 24, v, 'filled', 'MarkerEdgeColor', 'none');
            colormap(ax, parula);
            caxis(ax, cLim);
            cb = colorbar(ax); %#ok<NASGU>

            axis(ax, 'equal');
            axis(ax, 'off');
            view(ax, double(R.View));
            title(ax, b, 'Interpreter', 'none');
            hold(ax, 'off');
        end

        if iM == 1
            f_node1 = fig;
        else
            f_node2 = fig;
        end
    end

    % Global metrics: grouped bar plot (metric x band).
    f_global = [];
    if ~isempty(globalMetrics)
        M = nan(numel(globalMetrics), nBand);
        for iB = 1:nBand
            b = bandNames{iB};
            if ~isfield(res.(b), netField) || ~isstruct(res.(b).(netField))
                continue;
            end
            S = res.(b).(netField);
            for iG = 1:numel(globalMetrics)
                g = globalMetrics{iG};
                if isfield(S, g) && isfinite(S.(g))
                    M(iG, iB) = double(S.(g));
                end
            end
        end

        if any(isfinite(M), 'all')
            f_global = figure('Units', 'centimeters', 'Position', [0 0 12 7], ...
                'Visible', char(string(R.Visible)), 'Color', 'w');
            ax = axes(f_global); %#ok<LAXES>
            bar(ax, M, 'grouped');
            xticks(ax, 1:numel(globalMetrics));
            xticklabels(ax, globalMetrics);
            xtickangle(ax, 45);
            ylabel(ax, 'Value');
            title(ax, sprintf('%s | Global measures', cm), 'Interpreter', 'none');
            legend(ax, bandNames, 'Location', 'eastoutside', 'Color', 'none', 'Interpreter', 'none');
            box(ax, 'off');
            grid(ax, 'on');
        end
    end
end

