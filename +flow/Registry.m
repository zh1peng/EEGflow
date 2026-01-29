function reg = Registry(varargin)
%REGISTRY Initialize EEGflow operation registry.
% Usage:
%   reg = flow.Registry();                  % all modules
%   reg = flow.Registry('prep');            % only prep ops
%   reg = flow.Registry('analysis');        % only analysis ops
%   reg = flow.Registry('modules', {...});  % explicit list

    modules = parse_modules(varargin{:});

    reg = containers.Map('KeyType', 'char', 'ValueType', 'any');

    for i = 1:numel(modules)
        switch modules{i}
            case 'prep'
                register_prep(reg);
            case 'analysis'
                register_analysis(reg);
            otherwise
                error('Registry:BadModule', 'Unknown module "%s".', modules{i});
        end
    end

    % Optional aliases for LLM robustness (e.g., "prep.filter")
    keys = reg.keys();
    for i = 1:numel(keys)
        shortKey = keys{i};
        if ~isempty(strfind(shortKey, '.'))
            continue;
        end
        for j = 1:numel(modules)
            longKey = [modules{j} '.' shortKey];
            if ~reg.isKey(longKey)
                reg(longKey) = reg(shortKey);
            end
        end
    end

    fprintf('Registry initialized with %d operations (modules: %s).\n', ...
        reg.Count, strjoin(modules, ','));
end
