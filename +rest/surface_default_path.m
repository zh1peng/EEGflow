function p = surface_default_path(varargin)
%SURFACE_DEFAULT_PATH Return path to a built-in cortical surface mesh.
%
% Usage:
%   p = rest.surface_default_path();
%   p = rest.surface_default_path('surface_white_both');
%
% Output:
%   p : char, absolute path to a surface mesh shipped with EEGflow.
%
% Notes:
% - These meshes are intended for plotting (e.g., in rest.plot_* helpers).
% - See `resources/surface/README.md` for attribution/licensing.

    name = 'surface_white_both';
    if nargin >= 1 && ~isempty(varargin{1})
        name = lower(char(string(varargin{1})));
    end

    % repoRoot/+rest/surface_default_path.m -> repoRoot
    pkgDir = fileparts(mfilename('fullpath'));
    repoRoot = fileparts(pkgDir);

    switch name
        case {'surface_white_both','white_both','white'}
            p = fullfile(repoRoot, 'resources', 'surface', 'surface_white_both.mat');
        otherwise
            error('rest:surface_default_path:UnknownSurface', ...
                'Unknown surface name "%s".', name);
    end

    p = char(p);
end

