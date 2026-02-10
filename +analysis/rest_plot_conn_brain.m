function fig = rest_plot_conn_brain(connMatrix, nodePos, varargin)
%REST_PLOT_CONN_BRAIN Simple 3D "connectome" plot (publication-ready defaults).
%
% Usage:
%   fig = analysis.rest_plot_conn_brain(C, pos, 'SaveBase', 'out/alpha_connectome');
%
% Inputs:
%   connMatrix : n x n numeric connectivity matrix
%   nodePos    : n x 3 node positions (e.g., MNI in mm)
%
% Name-value options:
%   'Title'          : char/string
%   'EdgePercentile' : keep edges >= quantile (default 0.95)
%   'MaxEdges'       : cap number of edges (default 200)
%   'NodeSize'       : marker size (default 36)
%   'Colormap'       : colormap name (default 'turbo')
%   'SaveBase'       : base path without extension; when empty, no save
%   'Formats'        : cellstr extensions, default {'png','pdf'}
%   'Visible'        : 'on'|'off' (default 'off')
%   'Resolution'     : dpi for PNG (default 300)

    ip = inputParser;
    ip.addRequired('connMatrix', @(x) isnumeric(x) && ismatrix(x));
    ip.addRequired('nodePos', @(x) isnumeric(x) && size(x, 2) == 3);
    ip.addParameter('Title', '', @(s) ischar(s) || isstring(s));
    ip.addParameter('EdgePercentile', 0.95, @(x) isnumeric(x) && isscalar(x) && x > 0 && x < 1);
    ip.addParameter('MaxEdges', 200, @(x) isnumeric(x) && isscalar(x) && x > 0);
    ip.addParameter('NodeSize', 36, @(x) isnumeric(x) && isscalar(x) && x > 0);
    ip.addParameter('Colormap', 'turbo', @(s) ischar(s) || isstring(s));
    ip.addParameter('SaveBase', '', @(s) ischar(s) || isstring(s));
    ip.addParameter('Formats', {'png','pdf'}, @(x) iscellstr(x) || isstring(x));
    ip.addParameter('Visible', 'off', @(s) ischar(s) || isstring(s));
    ip.addParameter('Resolution', 300, @(x) isnumeric(x) && isscalar(x) && x > 0);
    ip.parse(connMatrix, nodePos, varargin{:});
    R = ip.Results;

    C = double(connMatrix);
    if size(C, 1) ~= size(C, 2)
        error('analysis:rest_plot_conn_brain:BadInput', 'connMatrix must be square.');
    end
    n = size(C, 1);
    pos = double(nodePos);
    if size(pos, 1) ~= n
        error('analysis:rest_plot_conn_brain:BadInput', 'nodePos must have n rows to match connMatrix.');
    end

    % Select edges by percentile on upper triangle.
    iu = triu(true(n), 1);
    w = C(iu);
    w = w(isfinite(w));
    if isempty(w)
        thresh = Inf;
    else
        thresh = quantile(w, R.EdgePercentile);
    end

    [ii, jj] = find(triu(C >= thresh, 1));
    ww = C(sub2ind([n n], ii, jj));
    keep = isfinite(ww);
    ii = ii(keep); jj = jj(keep); ww = ww(keep);

    % Cap edges (keep strongest).
    if numel(ww) > R.MaxEdges
        [~, ord] = sort(ww, 'descend');
        ord = ord(1:R.MaxEdges);
        ii = ii(ord); jj = jj(ord); ww = ww(ord);
    end

    fig = figure('Color', 'w', 'Visible', char(string(R.Visible)));
    ax = axes(fig); %#ok<LAXES>
    hold(ax, 'on');

    cmap = feval(char(string(R.Colormap)), 256);
    wmin = min(ww, [], 'omitnan');
    wmax = max(ww, [], 'omitnan');
    if isempty(wmin) || isempty(wmax) || ~isfinite(wmin) || ~isfinite(wmax) || wmax <= wmin
        wmin = 0; wmax = 1;
    end

    % Draw edges
    for k = 1:numel(ww)
        t = (ww(k) - wmin) / (wmax - wmin + eps);
        t = max(0, min(1, t));
        ci = 1 + floor(t * (size(cmap, 1) - 1));
        col = cmap(ci, :);
        lw = 0.5 + 2.5 * t;
        plot3(ax, pos([ii(k) jj(k)], 1), pos([ii(k) jj(k)], 2), pos([ii(k) jj(k)], 3), ...
            '-', 'Color', col, 'LineWidth', lw);
    end

    % Draw nodes on top
    scatter3(ax, pos(:, 1), pos(:, 2), pos(:, 3), R.NodeSize, ...
        'MarkerFaceColor', [0.05 0.05 0.05], 'MarkerEdgeColor', 'none');

    hold(ax, 'off');
    axis(ax, 'equal');
    axis(ax, 'off');
    view(ax, 3);
    title(ax, char(string(R.Title)), 'Interpreter', 'none');

    % Colorbar to interpret edge weights
    colormap(ax, cmap);
    cb = colorbar(ax);
    cb.Label.String = 'Connectivity';
    cb.Label.Interpreter = 'none';
    if isfinite(wmin) && isfinite(wmax)
        cb.Limits = [wmin wmax];
    end

    fig_apply_pub_style(fig);

    saveBase = char(string(R.SaveBase));
    if ~isempty(saveBase)
        fig_save(fig, saveBase, R.Formats, R.Resolution);
    end
end

