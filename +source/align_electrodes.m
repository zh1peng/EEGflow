function [elec2, qc] = align_electrodes(elec, dataLabels, varargin)
%ALIGN_ELECTRODES Reorder/subset electrodes to match data labels.

    ip = inputParser;
    ip.addRequired('elec', @isstruct);
    ip.addRequired('dataLabels', @(x) iscellstr(x) || isstring(x));
    ip.addParameter('Unit', '', @(s) ischar(s) || isstring(s));
    ip.parse(elec, dataLabels, varargin{:});
    R = ip.Results;

    if ~isfield(elec, 'label') || isempty(elec.label)
        error('source:align_electrodes:BadElec', 'Elec struct must contain label.');
    end

    dlab = cellstr(string(dataLabels(:)));
    elab = cellstr(string(elec.label(:)));
    [common, iData, iElec] = intersect(dlab, elab, 'stable');
    if isempty(common)
        error('source:align_electrodes:NoOverlap', ...
            'No overlapping labels between data and electrodes.');
    end

    elec2 = elec;
    elec2.label = elec.label(iElec);
    for f = {'chanpos','elecpos','chantype','chanunit'}
        name = f{1};
        if isfield(elec, name) && size(elec.(name), 1) >= max(iElec)
            elec2.(name) = elec.(name)(iElec, :);
        end
    end
    unit = char(string(R.Unit));
    if ~isempty(unit) && exist('ft_convert_units', 'file') == 2
        try
            elec2 = ft_convert_units(elec2, unit);
        catch
        end
    end

    qc = struct();
    qc.nDataChannels = numel(dlab);
    qc.nElecChannels = numel(elab);
    qc.nMatchedChannels = numel(common);
    qc.matchedLabels = common(:);
    qc.missingInElec = setdiff(dlab(:), common(:), 'stable');
    qc.extraInElec = setdiff(elab(:), common(:), 'stable');
    qc.dataIndex = iData(:);
    qc.elecIndex = iElec(:);
end
