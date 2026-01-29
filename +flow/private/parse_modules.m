function modules = parse_modules(varargin)
    if nargin == 0
        modules = {'prep', 'analysis'};
        return;
    end

    if nargin == 1 && (ischar(varargin{1}) || isstring(varargin{1}))
        modules = {char(varargin{1})};
        return;
    end

    ip = inputParser;
    addParameter(ip, 'modules', {'prep', 'analysis'}, @(x) iscell(x) || isstring(x));
    parse(ip, varargin{:});
    mods = ip.Results.modules;
    if isstring(mods)
        mods = cellstr(mods);
    end
    modules = cellfun(@char, mods, 'UniformOutput', false);
end
