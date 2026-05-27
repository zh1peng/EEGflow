function data = eeglab_to_fieldtrip_epoched(EEG, params)
%EEGLAB_TO_FIELDTRIP_EPOCHED Convert epoched EEGLAB data to FieldTrip raw.
%
% The output keeps trials as FieldTrip cells:
%   data.trial{t} = [nChannel x nTime]
%
% Source reconstruction functions use this as the sensor-space input before
% creating source/parcel virtual channels.

    if nargin < 2 || isempty(params), params = struct(); end

    if ~isstruct(EEG) || ~isfield(EEG, 'data') || isempty(EEG.data)
        error('source:eeglab_to_fieldtrip_epoched:BadEEG', 'EEG.data is empty or invalid.');
    end
    if ~isfield(EEG, 'trials') || EEG.trials < 1
        error('source:eeglab_to_fieldtrip_epoched:BadEEG', 'EEG.trials is invalid.');
    end
    if ~isfield(EEG, 'chanlocs') || isempty(EEG.chanlocs) || ~isfield(EEG.chanlocs, 'labels')
        error('source:eeglab_to_fieldtrip_epoched:BadEEG', 'EEG.chanlocs.labels is required.');
    end

    labels = {EEG.chanlocs.labels};
    labels = labels(:);

    if isfield(EEG, 'times') && ~isempty(EEG.times)
        tvec = double(EEG.times(:).') / 1000;
    else
        t0 = 0;
        if isfield(EEG, 'xmin') && ~isempty(EEG.xmin)
            t0 = double(EEG.xmin);
        end
        tvec = t0 + (0:(EEG.pnts-1)) / double(EEG.srate);
    end

    nTr = double(EEG.trials);
    data = struct();
    data.label = labels;
    data.fsample = double(EEG.srate);
    data.trial = cell(1, nTr);
    data.time = cell(1, nTr);
    data.sampleinfo = zeros(nTr, 2);

    for t = 1:nTr
        if nTr == 1
            X = EEG.data;
        else
            X = EEG.data(:, :, t);
        end
        data.trial{t} = double(X);
        data.time{t} = tvec;
        data.sampleinfo(t, :) = [1 size(data.trial{t}, 2)];
    end

    data = local_attach_elec(data, EEG, params);
end

function data = local_attach_elec(data, EEG, params)
    unit = local_get_param(params, 'Unit', 'mm');
    elec = local_get_param(params, 'Elec', []);
    if ~isempty(elec)
        data = local_align_elec(data, elec, unit);
        return;
    end

    tmplFile = char(string(local_get_param(params, 'ElectrodePath', '')));
    if isempty(tmplFile)
        tmplFile = char(string(local_get_param(params, 'TemplateElecFile', '')));
    end
    elecTemplate = char(string(local_get_param(params, 'ElectrodeTemplate', '')));
    if isempty(tmplFile) && ~isempty(elecTemplate)
        tmplFile = source.electrode_default_path(elecTemplate);
    end
    if ~isempty(tmplFile)
        if exist(tmplFile, 'file') ~= 2
            error('source:eeglab_to_fieldtrip_epoched:ElecNotFound', 'TemplateElecFile not found: %s', tmplFile);
        end
        if exist('ft_read_sens', 'file') ~= 2
            error('source:eeglab_to_fieldtrip_epoched:MissingFieldTrip', 'FieldTrip function ft_read_sens is required.');
        end
        data = local_align_elec(data, ft_read_sens(tmplFile), unit);
        return;
    end

    if isfield(EEG, 'chanlocs') && isfield(EEG.chanlocs, 'X')
        try
            X = [EEG.chanlocs.X]';
            Y = [EEG.chanlocs.Y]';
            Z = [EEG.chanlocs.Z]';
            if all(isfinite(X)) && all(isfinite(Y)) && all(isfinite(Z)) && any([X; Y; Z] ~= 0)
                elec = struct();
                elec.label = data.label;
                elec.chanpos = [X Y Z];
                elec.elecpos = elec.chanpos;
                elec.unit = unit;
                elec.type = 'eeglab';
                data.elec = elec;
            end
        catch
            % Electrode attachment is best-effort when only EEGLAB chanlocs
            % are available; FieldTrip will raise if geometry is insufficient.
        end
    end
end

function data = local_align_elec(data, elec, unit)
    if ~isfield(elec, 'label') || isempty(elec.label)
        error('source:eeglab_to_fieldtrip_epoched:BadElec', 'Elec struct missing label.');
    end

    dlab = cellstr(string(data.label));
    elab = cellstr(string(elec.label));
    [common, iData, iElec] = intersect(dlab, elab, 'stable');
    if isempty(common)
        error('source:eeglab_to_fieldtrip_epoched:BadElec', 'No overlapping channel labels between data and electrode definition.');
    end

    if numel(common) < numel(dlab)
        data.label = data.label(iData);
        for t = 1:numel(data.trial)
            data.trial{t} = data.trial{t}(iData, :);
        end
    end

    elec2 = elec;
    elec2.label = elec.label(iElec);
    if isfield(elec, 'chanpos'), elec2.chanpos = elec.chanpos(iElec, :); end
    if isfield(elec, 'elecpos'), elec2.elecpos = elec.elecpos(iElec, :); end
    if isfield(elec, 'chantype'), elec2.chantype = elec.chantype(iElec, :); end
    if isfield(elec, 'chanunit'), elec2.chanunit = elec.chanunit(iElec, :); end

    if exist('ft_convert_units', 'file') == 2
        try
            elec2 = ft_convert_units(elec2, unit);
        catch
        end
    end
    data.elec = elec2;
end

function v = local_get_param(params, field, default)
    v = default;
    if isstruct(params) && isfield(params, field) && ~isempty(params.(field))
        v = params.(field);
    end
end
