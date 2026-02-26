function [surf, usedPath] = load_surface(params, surfPath)
%LOAD_SURFACE Best-effort load cortical surface mesh for plotting.
%
% This attempts to locate and load a FieldTrip-readable surface mesh.
%
% Inputs:
%   params   : struct (optional). If it has .SurfaceModelPath, it is used.
%   surfPath : char/string (optional). If non-empty, it takes precedence.
%
% Outputs:
%   surf     : struct (FieldTrip mesh with fields like .pos/.tri), or []
%   usedPath : char, the path/name that successfully loaded, or ''
%
% Resolution order:
%   1) surfPath argument
%   2) params.SurfaceModelPath
%   3) EEGflow-shipped resource (rest.surface_default_path)
%   4) FieldTrip template anatomy/surface_white_both.mat (via ft_defaults location)
%   5) 'surface_white_both.mat' (resolved by FieldTrip/MATLAB path)

    surf = [];
    usedPath = '';

    if exist('ft_read_headshape', 'file') ~= 2
        return;
    end

    candidates = {};

    if nargin >= 2 && ~isempty(surfPath)
        candidates{end+1} = char(string(surfPath)); %#ok<AGROW>
    end

    if isstruct(params) && isfield(params, 'SurfaceModelPath') && ~isempty(params.SurfaceModelPath)
        candidates{end+1} = char(string(params.SurfaceModelPath)); %#ok<AGROW>
    end

    % EEGflow-shipped surface (if present).
    try
        p = rest.surface_default_path();
        candidates{end+1} = char(p); %#ok<AGROW>
    catch
        % best-effort only
    end

    % FieldTrip template surface (if FieldTrip is on path).
    ftDef = which('ft_defaults');
    if ~isempty(ftDef)
        ftRoot = fileparts(ftDef);
        candidates{end+1} = fullfile(ftRoot, 'template', 'anatomy', 'surface_white_both.mat'); %#ok<AGROW>
    end

    % Last resort: try resolving by name (e.g., current folder or FieldTrip template lookup).
    candidates{end+1} = 'surface_white_both.mat'; %#ok<AGROW>

    % Dedupe while preserving order (case-insensitive).
    uniq = {};
    for i = 1:numel(candidates)
        p = char(string(candidates{i}));
        if isempty(p), continue; end
        if any(strcmpi(uniq, p)), continue; end
        uniq{end+1} = p; %#ok<AGROW>
    end
    candidates = uniq;

    for i = 1:numel(candidates)
        p = candidates{i};
        if isempty(p), continue; end
        try
            s = ft_read_headshape(p);
            if isstruct(s) && isfield(s, 'pos') && ~isempty(s.pos)
                surf = s;
                usedPath = p;
                return;
            end
        catch
            % best-effort only
        end
    end
end

