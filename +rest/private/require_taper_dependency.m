function require_taper_dependency(taper, callerName)
%REQUIRE_TAPER_DEPENDENCY Validate optional taper-specific dependencies.

    if nargin < 2 || isempty(callerName)
        callerName = 'rest';
    end

    taper = lower(char(string(taper)));
    if strcmp(taper, 'dpss') && exist('dpss', 'file') ~= 2
        error('rest:MissingDependency:DPSS', ...
            ['%s requested Taper=''dpss'', but dpss() is not available. ' ...
             'Install Signal Processing Toolbox or set Taper to ''hanning''.'], ...
             callerName);
    end
end
