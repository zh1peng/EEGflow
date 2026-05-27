function [virt, src] = reconstruct_virtual_channels(data, spatialFilter, params)
%RECONSTRUCT_VIRTUAL_CHANNELS Apply a spatial filter to FieldTrip epochs.

    if nargin < 3 || isempty(params), params = struct(); end
    if exist('ft_virtualchannel', 'file') ~= 2
        error('source:reconstruct_virtual_channels:MissingFieldTrip', 'ft_virtualchannel is required.');
    end
    if ~isstruct(spatialFilter) || ~isfield(spatialFilter, 'pos') || ~isfield(spatialFilter, 'inside')
        error('source:reconstruct_virtual_channels:BadFilter', ...
            'Spatial filter must contain pos and inside.');
    end

    dataUse = data;
    bandpassRange = local_get(params, 'BandpassRange', []);
    if isempty(bandpassRange) && isfield(params, 'FreqBand') && isfield(params, 'BandName')
        bandName = char(string(params.BandName));
        if isfield(params.FreqBand, bandName)
            bandpassRange = params.FreqBand.(bandName);
        end
    end
    if ~isempty(bandpassRange)
        cfg = [];
        cfg.bpfilter = 'yes';
        cfg.bpfreq = bandpassRange;
        dataUse = ft_preprocessing(cfg, dataUse);
    end

    insideIdx = local_inside_indices(spatialFilter);
    cfg = [];
    cfg.pos = spatialFilter.pos(insideIdx, :);
    virt = ft_virtualchannel(cfg, dataUse, spatialFilter);

    src = struct();
    src.label = virt.label(:);
    src.trial = virt.trial;
    src.time = virt.time;
    src.fsample = virt.fsample;
    src.level = char(string(local_get(params, 'OutputLevel', 'source')));
    src.source_pos = double(spatialFilter.pos(insideIdx, :));
    src.source_inside_idx = insideIdx(:);
    src.unit = local_get(params, 'Unit', local_get(spatialFilter, 'unit', ''));
    src.cfg = params;
end

function idx = local_inside_indices(spatialFilter)
    inside = spatialFilter.inside;
    if islogical(inside)
        idx = find(inside(:));
    else
        idx = double(inside(:));
    end
end

function v = local_get(s, field, default)
    v = default;
    if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
        v = s.(field);
    end
end
