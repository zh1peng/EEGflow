function p = atlas_default_path(template)
%ATLAS_DEFAULT_PATH Resolve bundled coarse atlas templates.

    if nargin < 1 || isempty(template)
        template = 'schaefer100';
    end
    key = regexprep(lower(char(string(template))), '[^a-z0-9]', '');
    root = fileparts(fileparts(mfilename('fullpath')));

    switch key
        case {'schaefer100','schaefer2018100','schaefer1007networks'}
            p = fullfile(root, 'resources', 'atlas', ...
                'Schaefer2018_100Parcels_7Networks_order_FSLMNI152_1mm.Centroid_RAS.csv');
        otherwise
            error('source:atlas_default_path:UnknownTemplate', ...
                'Unknown atlas template "%s". Bundled default: Schaefer100.', char(string(template)));
    end

    if exist(p, 'file') ~= 2
        error('source:atlas_default_path:NotFound', 'Atlas template file not found: %s', p);
    end
end
