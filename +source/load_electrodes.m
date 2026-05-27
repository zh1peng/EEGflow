function elec = load_electrodes(EEG, params)
%LOAD_ELECTRODES Resolve electrodes from struct, template, path, or EEG.chanlocs.

    if nargin < 1, EEG = []; end
    if nargin < 2 || isempty(params), params = struct(); end
    unit = char(string(local_get(params, 'Unit', 'mm')));

    elec = local_get(params, 'Elec', []);
    if ~isempty(elec)
        elec = local_convert_units(elec, unit);
        return;
    end

    elecPath = char(string(local_get(params, 'ElectrodePath', '')));
    if isempty(elecPath)
        elecPath = char(string(local_get(params, 'TemplateElecFile', '')));
    end
    elecTemplate = char(string(local_get(params, 'ElectrodeTemplate', '')));
    if isempty(elecPath) && ~isempty(elecTemplate)
        elecPath = source.electrode_default_path(elecTemplate);
    end
    if ~isempty(elecPath)
        if exist(elecPath, 'file') ~= 2
            error('source:load_electrodes:NotFound', 'Electrode file not found: %s', elecPath);
        end
        if exist('ft_read_sens', 'file') ~= 2
            error('source:load_electrodes:MissingFieldTrip', 'ft_read_sens is required.');
        end
        elec = local_convert_units(ft_read_sens(elecPath), unit);
        return;
    end

    if isstruct(EEG) && isfield(EEG, 'chanlocs') && ~isempty(EEG.chanlocs) && ...
            isfield(EEG.chanlocs, 'X') && isfield(EEG.chanlocs, 'labels')
        labels = {EEG.chanlocs.labels}';
        X = [EEG.chanlocs.X]';
        Y = [EEG.chanlocs.Y]';
        Z = [EEG.chanlocs.Z]';
        if all(isfinite(X)) && all(isfinite(Y)) && all(isfinite(Z)) && any([X; Y; Z] ~= 0)
            elec = struct();
            elec.label = labels;
            elec.chanpos = [X Y Z];
            elec.elecpos = elec.chanpos;
            elec.unit = unit;
            elec.type = 'eeglab';
            return;
        end
    end

    error('source:load_electrodes:MissingElectrodes', ...
        'Provide Elec, ElectrodePath, ElectrodeTemplate, TemplateElecFile, or EEG.chanlocs XYZ.');
end

function elec = local_convert_units(elec, unit)
    if exist('ft_convert_units', 'file') == 2 && ~isempty(unit)
        try
            elec = ft_convert_units(elec, unit);
        catch
        end
    end
end

function v = local_get(s, field, default)
    v = default;
    if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
        v = s.(field);
    end
end
