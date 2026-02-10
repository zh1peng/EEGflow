function fig = rest_plot_conn_matrix(connMatrix, varargin)
%REST_PLOT_CONN_MATRIX Publication-ready connectivity matrix plot.
%
% Usage:
%   fig = analysis.rest_plot_conn_matrix(C, 'SaveBase', 'out/alpha_dwpli');
%
% Inputs:
%   connMatrix : n x n numeric
%
% Name-value options:
%   'Labels'     : cellstr labels (n x 1), optional
%   'Title'      : char/string
%   'CLim'       : [cmin cmax] or [] (auto)
%   'Colormap'   : colormap name (default 'parula')
%   'SaveBase'   : base path without extension; when empty, no save
%   'Formats'    : cellstr extensions, default {'png','pdf'}
%   'Visible'    : 'on'|'off' (default 'off')
%   'Resolution' : dpi for PNG (default 300)

    ip = inputParser;
    ip.addRequired('connMatrix', @(x) isnumeric(x) && ismatrix(x));
    ip.addParameter('Labels', {}, @(x) isempty(x) || iscellstr(x) || isstring(x));
    ip.addParameter('Title', '', @(s) ischar(s) || isstring(s));
    ip.addParameter('CLim', [], @(x) isempty(x) || (isnumeric(x) && numel(x) == 2));
    ip.addParameter('Colormap', 'parula', @(s) ischar(s) || isstring(s));
    ip.addParameter('SaveBase', '', @(s) ischar(s) || isstring(s));
    ip.addParameter('Formats', {'png','pdf'}, @(x) iscellstr(x) || isstring(x));
    ip.addParameter('Visible', 'off', @(s) ischar(s) || isstring(s));
    ip.addParameter('Resolution', 300, @(x) isnumeric(x) && isscalar(x) && x > 0);
    ip.parse(connMatrix, varargin{:});
    R = ip.Results;

    C = double(connMatrix);
    if size(C, 1) ~= size(C, 2)
        error('analysis:rest_plot_conn_matrix:BadInput', 'connMatrix must be square.');
    end

    fig = figure('Color', 'w', 'Visible', char(string(R.Visible)));
    ax = axes(fig); %#ok<LAXES>

    imagesc(ax, C);
    axis(ax, 'image');
    set(ax, 'YDir', 'normal');
    colormap(ax, char(string(R.Colormap)));
    cb = colorbar(ax); %#ok<NASGU>

    if isempty(R.CLim)
        vmax = max(C(~isnan(C)), [], 'all');
        if isempty(vmax) || ~isfinite(vmax)
            vmax = 1;
        end
        if vmax <= 0, vmax = 1; end
        clim(ax, [0 vmax]);
    else
        clim(ax, double(R.CLim));
    end

    n = size(C, 1);
    labels = R.Labels;
    if isstring(labels), labels = cellstr(labels); end
    if ~isempty(labels) && numel(labels) == n && n <= 48
        xticks(ax, 1:n);
        yticks(ax, 1:n);
        xticklabels(ax, labels);
        yticklabels(ax, labels);
        xtickangle(ax, 45);
    else
        xticks(ax, []);
        yticks(ax, []);
    end

    title(ax, char(string(R.Title)), 'Interpreter', 'none');

    fig_apply_pub_style(fig);

    saveBase = char(string(R.SaveBase));
    if ~isempty(saveBase)
        fig_save(fig, saveBase, R.Formats, R.Resolution);
    end
end

