function p = atlas_default_path(varargin)
%ATLAS_DEFAULT_PATH Return path to a built-in atlas centroid CSV.
%
% Usage:
%   p = rest.atlas_default_path();
%   p = rest.atlas_default_path('schaefer2018_100_7networks');
%
% Output:
%   p : char, absolute path to a centroid CSV shipped with EEGflow.
%
% Notes:
%   - The default atlas shipped with EEGflow is a Schaefer2018 centroid CSV
%     (100 parcels, 7 networks; MNI RAS, mm).
%   - See `resources/atlas/README.md` for attribution/licensing of the
%     shipped atlas file(s).

    name = 'schaefer2018_100_7networks';
    if nargin >= 1 && ~isempty(varargin{1})
        name = lower(char(string(varargin{1})));
    end

    % repoRoot/+rest/atlas_default_path.m -> repoRoot
    pkgDir = fileparts(mfilename('fullpath'));
    repoRoot = fileparts(pkgDir);

    switch name
        case {'schaefer2018_100_7networks','schaefer100','schaefer'}
            p = fullfile(repoRoot, 'resources', 'atlas', ...
                'Schaefer2018_100Parcels_7Networks_order_FSLMNI152_1mm.Centroid_RAS.csv');
        otherwise
            error('rest:atlas_default_path:UnknownAtlas', ...
                'Unknown atlas name "%s".', name);
    end

    p = char(p);
end

