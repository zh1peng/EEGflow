function pos = atlas_table_to_pos(T)
%ATLAS_TABLE_TO_POS Extract Nx3 centroid positions from an atlas table.
%
% Supports common centroid CSV variants:
%   - columns named R,A,S (e.g., Schaefer centroid RAS)
%   - columns named X,Y,Z
%   - case-insensitive match

    if ~istable(T)
        error('rest:atlas_table_to_pos:BadInput', 'Input must be a table.');
    end

    vars = lower(string(T.Properties.VariableNames));

    idxR = find(vars == "r", 1);
    idxA = find(vars == "a", 1);
    idxS = find(vars == "s", 1);
    if ~isempty(idxR) && ~isempty(idxA) && ~isempty(idxS)
        pos = [T{:, idxR}, T{:, idxA}, T{:, idxS}];
        return;
    end

    idxX = find(vars == "x", 1);
    idxY = find(vars == "y", 1);
    idxZ = find(vars == "z", 1);
    if ~isempty(idxX) && ~isempty(idxY) && ~isempty(idxZ)
        pos = [T{:, idxX}, T{:, idxY}, T{:, idxZ}];
        return;
    end

    error('rest:atlas_table_to_pos:BadAtlas', 'Atlas table must have columns (R,A,S) or (X,Y,Z).');
end

