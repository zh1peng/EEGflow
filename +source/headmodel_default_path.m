function p = headmodel_default_path(template)
%HEADMODEL_DEFAULT_PATH Resolve common FieldTrip/EEGLAB headmodel templates.

    if nargin < 1 || isempty(template)
        template = 'fieldtrip_standard_bem';
    end
    key = regexprep(lower(char(string(template))), '[^a-z0-9]', '');

    ftRoot = getenv('FIELDTRIP_ROOT');
    eeglabRoot = getenv('EEGLAB_ROOT');

    switch key
        case {'fieldtripstandardbem','fieldtripstandardvolumebem'}
            p = fullfile(ftRoot, 'template', 'headmodel', 'standard_bem.mat');
        case {'fieldtripstandardsingleshell','fieldtripsingleshell'}
            p = fullfile(ftRoot, 'template', 'headmodel', 'standard_singleshell.mat');
        case {'eeglabdipfitstandardbem','dipfitstandardbem'}
            p = fullfile(eeglabRoot, 'plugins', 'dipfit', 'standard_BEM', 'standard_vol.mat');
        otherwise
            error('source:headmodel_default_path:UnknownTemplate', ...
                'Unknown headmodel template "%s".', char(string(template)));
    end

    if isempty(fileparts(p)) || exist(p, 'file') ~= 2
        error('source:headmodel_default_path:NotFound', ...
            'Template "%s" was not found. Set FIELDTRIP_ROOT or EEGLAB_ROOT, or pass HeadModelPath.', ...
            char(string(template)));
    end
end
