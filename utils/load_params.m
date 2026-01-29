function Params = load_params(src, varargin)
%LOAD_PARAMS Load Params from a .m script or a .json file (or pass-through struct).
%
% Usage:
%   Params = load_params('config.m');
%   Params = load_params('config.json');
%   Params = load_params(ParamsStruct);              % pass-through
%
% Options:
%   Params = load_params(..., 'VarName', 'Params');  % variable to read from .m script (default: 'Params')
%
% Notes:
% - .m: expects a script that creates a variable named VarName (default 'Params')
%   OR a function (same name as file) with no inputs returning a struct.
% - .json: uses jsondecode(fileread(...)).
% - After loading (both .m/.json), it normalizes shapes so that any CELL VECTOR
%   becomes a 1xN row cell (fixes {Nx1 cell} vs {1xN cell} issues).

p = inputParser;
p.addRequired('src');
p.addParameter('VarName', 'Params', @(s) ischar(s) || isstring(s));
p.parse(src, varargin{:});
varName = char(p.Results.VarName);

% Pass-through
if isstruct(src)
    Params = normalize_params_shape(src);
    return;
end

if ~(ischar(src) || isstring(src))
    error('load_params:InvalidInput', 'src must be a struct or a file path (.m/.json).');
end

src = char(strtrim(src));

% Resolve file path (try adding extensions if missing)
[pathstr, name, ext] = fileparts(src);
candidates = {};

if isempty(ext)
    candidates{end+1} = fullfile(pathstr, [name '.m']);
    candidates{end+1} = fullfile(pathstr, [name '.json']);
else
    candidates{end+1} = src;
end

found = '';
for i = 1:numel(candidates)
    if exist(candidates{i}, 'file') == 2
        found = candidates{i};
        break;
    end
end

if isempty(found)
    error('load_params:FileNotFound', 'Cannot find file: %s', src);
end

[folder, base, ext] = fileparts(found);
ext = lower(ext);

switch ext
    case '.json'
        txt = fileread(found);
        Params = jsondecode(txt);
        if ~isstruct(Params)
            error('load_params:InvalidJSON', 'Top-level JSON must decode to a struct/object.');
        end

    case '.m'
        % Run as script in isolated function workspace
        origDir = pwd;
        c = onCleanup(@() cd(origDir));
        if ~isempty(folder), cd(folder); end

        % 1) Try script-style loading (run)
        try
            run(found);
        catch runME
            % 2) Fallback: function with no inputs returning struct
            try
                if ~isempty(folder)
                    addpath(folder);
                    rp = onCleanup(@() rmpath(folder));
                end
                fh = str2func(base);
                out = fh();
                if isstruct(out)
                    Params = out;
                else
                    rethrow(runME);
                end
            catch
                rethrow(runME);
            end
        end

        if ~exist('Params','var') && exist(varName, 'var') ~= 1
            error('load_params:VarMissing', ...
                'Loaded %s but did not find variable "%s".', found, varName);
        end

        if exist(varName, 'var') == 1
            Params = eval(varName);
        end

        if ~isstruct(Params)
            error('load_params:NotStruct', ...
                'Variable "%s" exists but is not a struct.', varName);
        end

    otherwise
        error('load_params:UnsupportedExt', 'Unsupported file type: %s', ext);
end

% Normalize shapes for downstream robustness (no field hard-coding)
Params = normalize_params_shape(Params);

% Normalize key fields to align .m and .json behavior
Params = normalize_params_fields(Params);

end

% ---------- local helper ----------
function x = normalize_params_shape(x)
% Normalize struct content:
% - make any cell vector a row cell (1xN)
% - convert string arrays to cellstr (preserves shape)
% - recurse into structs / cells / struct arrays

    if isstruct(x)
        % struct arrays supported
        for k = 1:numel(x)
            fn = fieldnames(x(k));
            for i = 1:numel(fn)
                f = fn{i};
                x(k).(f) = normalize_params_shape(x(k).(f));
            end
        end

    elseif isstring(x)
        x = cellstr(x);

    elseif iscell(x)
        for i = 1:numel(x)
            x{i} = normalize_params_shape(x{i});
        end

        % Only coerce true vectors; keep cell matrices intact
        if isvector(x)
            x = x(:)';  % force 1xN
        end
    elseif isnumeric(x)
        % JSON arrays often decode as column vectors; coerce to row for parity with .m templates
        if isvector(x) && ~isempty(x)
            x = x(:).';
        end
    end
end

function Params = normalize_params_fields(Params)
    if ~isstruct(Params), return; end

    % ChanInfo label fields to row cellstr
    if isfield(Params, 'ChanInfo') && isstruct(Params.ChanInfo)
        labelFields = {'RefChanLabel','EOGChanLabel','KnownBadChanLabel','Chan2remove','ECGChanLabel','OtherChanLabel'};
        for i = 1:numel(labelFields)
            f = labelFields{i};
            if isfield(Params.ChanInfo, f)
                Params.ChanInfo.(f) = to_cellstr_row(Params.ChanInfo.(f));
            end
        end
    end

    % BadChan defaults derived from ChanInfo when missing/empty/'auto'
    if isfield(Params, 'BadChan') && isstruct(Params.BadChan)
        if isfield(Params.BadChan, 'ExcludeLabel')
            Params.BadChan.ExcludeLabel = to_cellstr_row(Params.BadChan.ExcludeLabel);
        end
        if ~isfield(Params.BadChan, 'ExcludeLabel') || isempty(Params.BadChan.ExcludeLabel) || is_auto(Params.BadChan.ExcludeLabel)
            if isfield(Params, 'ChanInfo') && isstruct(Params.ChanInfo)
                Params.BadChan.ExcludeLabel = [ ...
                    get_cell(Params.ChanInfo, 'EOGChanLabel'), ...
                    get_cell(Params.ChanInfo, 'RefChanLabel'), ...
                    get_cell(Params.ChanInfo, 'OtherChanLabel'), ...
                    get_cell(Params.ChanInfo, 'ECGChanLabel')];
            end
        end

        if isfield(Params.BadChan, 'KnownBadLabel')
            Params.BadChan.KnownBadLabel = to_cellstr_row(Params.BadChan.KnownBadLabel);
        end
        if ~isfield(Params.BadChan, 'KnownBadLabel') || isempty(Params.BadChan.KnownBadLabel) || is_auto(Params.BadChan.KnownBadLabel)
            if isfield(Params, 'ChanInfo') && isfield(Params.ChanInfo, 'KnownBadChanLabel')
                Params.BadChan.KnownBadLabel = Params.ChanInfo.KnownBadChanLabel;
            end
        end
    end

    % BadIC defaults derived from ChanInfo when missing/empty/'auto'
    if isfield(Params, 'BadIC') && isstruct(Params.BadIC)
        if isfield(Params.BadIC, 'EOGChanLabel')
            Params.BadIC.EOGChanLabel = to_cellstr_row(Params.BadIC.EOGChanLabel);
        end
        if ~isfield(Params.BadIC, 'EOGChanLabel') || isempty(Params.BadIC.EOGChanLabel) || is_auto(Params.BadIC.EOGChanLabel)
            if isfield(Params, 'ChanInfo') && isfield(Params.ChanInfo, 'EOGChanLabel')
                Params.BadIC.EOGChanLabel = Params.ChanInfo.EOGChanLabel;
            end
        end
    end

    % Reref defaults and shape normalization
    if isfield(Params, 'Reref') && isstruct(Params.Reref)
        if isfield(Params.Reref, 'ExcludeLabel')
            Params.Reref.ExcludeLabel = to_cellstr_row(Params.Reref.ExcludeLabel);
        else
            Params.Reref.ExcludeLabel = {};
        end
    end
end

function v = to_cellstr_row(v)
    if isempty(v)
        v = {};
    elseif ischar(v)
        v = {v};
    elseif isstring(v)
        v = cellstr(v);
    elseif iscell(v)
        v = cellfun(@to_char, v, 'UniformOutput', false);
    else
        return;
    end
    v = v(:).';
end

function v = get_cell(S, fname)
    if isfield(S, fname)
        v = to_cellstr_row(S.(fname));
    else
        v = {};
    end
end

function tf = is_auto(v)
    if iscell(v) && numel(v) == 1
        v = v{1};
    end
    tf = (ischar(v) || (isstring(v) && isscalar(v))) && strcmpi(char(v), 'auto');
end

function v = to_char(v)
    if isstring(v) && isscalar(v)
        v = char(v);
    end
end
