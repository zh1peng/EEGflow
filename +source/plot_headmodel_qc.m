function fig = plot_headmodel_qc(geometry, varargin)
%PLOT_HEADMODEL_QC Visualize electrode/headmodel alignment.

    ip = inputParser;
    ip.addRequired('geometry', @(x) isstruct(x));
    ip.addParameter('Visible', 'off', @(s) ischar(s) || isstring(s));
    ip.addParameter('OutputFile', '', @(s) ischar(s) || isstring(s));
    ip.addParameter('View', [135 25], @(x) isnumeric(x) && numel(x) == 2);
    ip.parse(geometry, varargin{:});
    R = ip.Results;

    if isfield(geometry, 'geometry')
        geometry = geometry.geometry;
    end
    if isfield(geometry, 'source') && isfield(geometry.source, 'geometry')
        geometry = geometry.source.geometry;
    end
    if ~isfield(geometry, 'elec') || ~isfield(geometry, 'headmodel')
        error('source:plot_headmodel_qc:BadGeometry', ...
            'Provide state.source.geometry or a struct with headmodel and elec.');
    end

    headshape = local_headshape(geometry.headmodel);
    ep = local_elec_pos(geometry.elec);
    fig = figure('Visible', char(string(R.Visible)), 'Color', 'w');
    hold on;
    if isstruct(headshape) && isfield(headshape, 'tri') && ~isempty(headshape.tri)
        patch('Vertices', headshape.pos, 'Faces', headshape.tri, ...
            'FaceColor', [0.85 0.85 0.85], 'EdgeColor', 'none', 'FaceAlpha', 0.18);
    elseif isstruct(headshape) && isfield(headshape, 'pos') && ~isempty(headshape.pos)
        plot3(headshape.pos(:,1), headshape.pos(:,2), headshape.pos(:,3), '.', ...
            'Color', [0.85 0.85 0.85], 'MarkerSize', 2);
    end
    scatter3(ep(:,1), ep(:,2), ep(:,3), 28, 'filled', 'MarkerFaceColor', [0.1 0.35 0.85]);
    axis equal vis3d;
    grid on;
    xlabel('X'); ylabel('Y'); zlabel('Z');
    title('Headmodel / electrode QC');
    view(double(R.View));
    try
        camlight headlight;
        lighting gouraud;
    catch
    end
    hold off;

    outFile = char(string(R.OutputFile));
    if ~isempty(outFile)
        [outDir, ~, ~] = fileparts(outFile);
        if ~isempty(outDir) && ~isfolder(outDir), mkdir(outDir); end
        exportgraphics(fig, outFile, 'Resolution', 150);
    end
end

function headshape = local_headshape(headmodel)
    headshape = [];
    if isfield(headmodel, 'bnd') && ~isempty(headmodel.bnd)
        score = nan(numel(headmodel.bnd), 1);
        for i = 1:numel(headmodel.bnd)
            if isfield(headmodel.bnd(i), 'pos') && ~isempty(headmodel.bnd(i).pos)
                pos = double(headmodel.bnd(i).pos);
                ctr = median(pos, 1, 'omitnan');
                score(i) = median(sqrt(sum((pos - ctr).^2, 2)), 'omitnan');
            end
        end
        [~, idx] = max(score);
        headshape = headmodel.bnd(idx);
    elseif isfield(headmodel, 'pos') && ~isempty(headmodel.pos)
        headshape = struct('pos', headmodel.pos);
    end
end

function pos = local_elec_pos(elec)
    if isfield(elec, 'chanpos') && ~isempty(elec.chanpos)
        pos = double(elec.chanpos);
    elseif isfield(elec, 'elecpos') && ~isempty(elec.elecpos)
        pos = double(elec.elecpos);
    else
        error('source:plot_headmodel_qc:BadElec', 'Elec must contain chanpos or elecpos.');
    end
end
