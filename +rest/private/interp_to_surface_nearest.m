function vtxVal = interp_to_surface_nearest(surfPos, nodePos, nodeVal)
%INTERP_TO_SURFACE_NEAREST Nearest-neighbor interpolation from nodes to vertices.
%
% Inputs:
%   surfPos : [nV x 3] surface vertex positions
%   nodePos : [nN x 3] node (ROI) positions
%   nodeVal : [nN x 1] node values to map onto the surface
%
% Output:
%   vtxVal  : [nV x 1] value at each surface vertex, assigned from the
%             nearest node in Euclidean distance.
%
% Notes:
% - This mimics the DISCOVER-EEG use of ft_sourceinterpolate(...,'nearest')
%   for simple visualization.

    vtxVal = nan(size(surfPos, 1), 1);

    if isempty(surfPos) || isempty(nodePos) || isempty(nodeVal)
        return;
    end

    surfPos = double(surfPos);
    nodePos = double(nodePos);
    nodeVal = double(nodeVal(:));

    if size(surfPos, 2) ~= 3 || size(nodePos, 2) ~= 3
        return;
    end

    keep = isfinite(nodeVal) & all(isfinite(nodePos), 2);
    if ~any(keep)
        return;
    end
    nodePos = nodePos(keep, :);
    nodeVal = nodeVal(keep);

    nV = size(surfPos, 1);
    nN = size(nodePos, 1);

    minD2 = inf(nV, 1);
    idxMin = ones(nV, 1);

    % Loop over nodes (typically ~100) to avoid allocating an nV-by-nN matrix.
    for i = 1:nN
        d = surfPos - nodePos(i, :);
        d2 = sum(d.^2, 2);
        m = d2 < minD2;
        minD2(m) = d2(m); %#ok<NASGU>
        idxMin(m) = i;
    end

    vtxVal = nodeVal(idxMin);
end

