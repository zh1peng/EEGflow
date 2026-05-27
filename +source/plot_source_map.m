function fig = plot_source_map(srcOrPos, values, varargin)
%PLOT_SOURCE_MAP Plot scalar values on source/parcel coordinates.

    if nargin < 2, values = []; end
    ip = inputParser;
    ip.addRequired('srcOrPos', @(x) isstruct(x) || (isnumeric(x) && size(x, 2) == 3));
    ip.addRequired('values', @(x) isempty(x) || isnumeric(x));
    ip.addParameter('Visible', 'off', @(s) ischar(s) || isstring(s));
    ip.addParameter('OutputFile', '', @(s) ischar(s) || isstring(s));
    ip.addParameter('Title', 'Source map', @(s) ischar(s) || isstring(s));
    ip.addParameter('MarkerSize', 36, @(x) isnumeric(x) && isscalar(x) && x > 0);
    ip.addParameter('View', [0 90], @(x) isnumeric(x) && numel(x) == 2);
    ip.parse(srcOrPos, values, varargin{:});
    R = ip.Results;

    if isstruct(srcOrPos)
        if isfield(srcOrPos, 'source_pos')
            pos = double(srcOrPos.source_pos);
        elseif isfield(srcOrPos, 'pos')
            pos = double(srcOrPos.pos);
        else
            error('source:plot_source_map:MissingPos', 'Struct must contain source_pos or pos.');
        end
    else
        pos = double(srcOrPos);
    end

    if isempty(values)
        values = ones(size(pos, 1), 1);
    end
    values = double(values(:));
    if numel(values) ~= size(pos, 1)
        error('source:plot_source_map:BadValues', 'values length must match source positions.');
    end

    fig = figure('Visible', char(string(R.Visible)), 'Color', 'w');
    scatter3(pos(:,1), pos(:,2), pos(:,3), double(R.MarkerSize), values, 'filled', ...
        'MarkerEdgeColor', 'none');
    axis equal;
    axis off;
    view(double(R.View));
    colormap(parula);
    colorbar;
    title(char(string(R.Title)), 'Interpreter', 'none');

    outFile = char(string(R.OutputFile));
    if ~isempty(outFile)
        [outDir, ~, ~] = fileparts(outFile);
        if ~isempty(outDir) && ~isfolder(outDir), mkdir(outDir); end
        exportgraphics(fig, outFile, 'Resolution', 150);
    end
end
