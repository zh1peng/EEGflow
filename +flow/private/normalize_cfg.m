function cfg = normalize_cfg(cfg)
%NORMALIZE_CFG Normalize jsondecoded config fields to expected types/shapes.
%
% Converts common fields to char/cellstr and ensures numeric bands are row vectors.

    if isfield(cfg, 'Crop')
        if isfield(cfg.Crop, 'StartMarker'), cfg.Crop.StartMarker = to_char(cfg.Crop.StartMarker); end
        if isfield(cfg.Crop, 'EndMarker'),   cfg.Crop.EndMarker   = to_char(cfg.Crop.EndMarker);   end
    end
    if isfield(cfg, 'Powerline') && isfield(cfg.Powerline, 'Method')
        cfg.Powerline.Method = to_char(cfg.Powerline.Method);
    end
    if isfield(cfg, 'BadChan')
        cfg.BadChan.ExcludeLabel   = to_cellstr(cfg.BadChan.ExcludeLabel);
        cfg.BadChan.KnownBadLabel  = to_row(cfg.BadChan.KnownBadLabel);
        if isfield(cfg.BadChan, 'Spec_FreqRange'), cfg.BadChan.Spec_FreqRange = to_row(cfg.BadChan.Spec_FreqRange); end
        if isfield(cfg.BadChan, 'CleanDrift_Band'), cfg.BadChan.CleanDrift_Band = to_row(cfg.BadChan.CleanDrift_Band); end
        if isfield(cfg.BadChan, 'FASTER_Bandpass'), cfg.BadChan.FASTER_Bandpass = to_row(cfg.BadChan.FASTER_Bandpass); end
        if isfield(cfg.BadChan, 'NormOn'), cfg.BadChan.NormOn = to_char(cfg.BadChan.NormOn); end
    end
    if isfield(cfg, 'ChanInfo') && isfield(cfg.ChanInfo, 'Chan2remove')
        cfg.ChanInfo.Chan2remove = to_cellstr(cfg.ChanInfo.Chan2remove);
    end
    if isfield(cfg, 'Reref') && isfield(cfg.Reref, 'ExcludeLabel')
        cfg.Reref.ExcludeLabel = to_cellstr(cfg.Reref.ExcludeLabel);
    end
end

function out = to_row(x)
    if isempty(x), out = x; return; end
    if isnumeric(x), out = x(:)'; return; end
    out = x;
end

function out = to_char(x)
    if isstring(x), out = char(x); return; end
    if isnumeric(x), out = num2str(x); return; end
    out = x;
end

function out = to_cellstr(x)
    if isempty(x), out = {}; return; end
    if ischar(x), out = {x}; return; end
    if isstring(x), out = cellstr(x); return; end
    if iscell(x)
        out = cellfun(@to_char, x, 'UniformOutput', false);
        return;
    end
    out = x;
end
