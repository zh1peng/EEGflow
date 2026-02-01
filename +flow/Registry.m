function reg = Registry(scope)
%REGISTRY Initialize EEGflow operation registry.
% Usage:
%   reg = flow.Registry();                  % all ops
%   reg = flow.Registry('prep');            % prep only
%   reg = flow.Registry('analysis');        % analysis only

    if nargin < 1 || isempty(scope)
        scope = 'all';
    end
    scope = lower(char(scope));

    reg = containers.Map('KeyType', 'char', 'ValueType', 'any');

    switch scope
        case {'all','both'}
            register_prep(reg);
            register_analysis(reg);
        case {'prep'}
            register_prep(reg);
        case {'analysis'}
            register_analysis(reg);
        otherwise
            error('Registry:BadScope', 'Unknown scope "%s". Use: all|prep|analysis.', scope);
    end

    % Optional aliases for LLM robustness (e.g., "prep.filter")
    keys = reg.keys();
    for i = 1:numel(keys)
        shortKey = keys{i};
        if ~isempty(strfind(shortKey, '.'))
            continue;
        end
        if any(strcmp(scope, {'all','both','prep'}))
            longKey = ['prep.' shortKey];
            if ~reg.isKey(longKey)
                reg(longKey) = reg(shortKey);
            end
        end
        if any(strcmp(scope, {'all','both','analysis'}))
            longKey = ['analysis.' shortKey];
            if ~reg.isKey(longKey)
                reg(longKey) = reg(shortKey);
            end
        end
    end

    fprintf('Registry initialized with %d operations (scope: %s).\n', reg.Count, scope);
end
