function p = electrode_default_path(template)
%ELECTRODE_DEFAULT_PATH Resolve common FieldTrip electrode templates.

    if nargin < 1 || isempty(template)
        template = 'fieldtrip_standard_1005';
    end
    key = regexprep(lower(char(string(template))), '[^a-z0-9]', '');
    ftRoot = getenv('FIELDTRIP_ROOT');

    switch key
        case {'fieldtripstandard1005','standard1005'}
            p = fullfile(ftRoot, 'template', 'electrode', 'standard_1005.elc');
        case {'fieldtripstandard1020','standard1020'}
            p = fullfile(ftRoot, 'template', 'electrode', 'standard_1020.elc');
        case {'fieldtripgsnhydrocel128','gsnhydrocel128'}
            p = fullfile(ftRoot, 'template', 'electrode', 'GSN-HydroCel-128.sfp');
        case {'fieldtripeasycapm1','easycapm1'}
            p = fullfile(ftRoot, 'template', 'electrode', 'easycap-M1.txt');
        otherwise
            error('source:electrode_default_path:UnknownTemplate', ...
                'Unknown electrode template "%s".', char(string(template)));
    end

    if exist(p, 'file') ~= 2
        error('source:electrode_default_path:NotFound', ...
            'Template "%s" was not found. Set FIELDTRIP_ROOT or pass ElectrodePath.', ...
            char(string(template)));
    end
end
