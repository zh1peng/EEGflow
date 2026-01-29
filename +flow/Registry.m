function reg = Registry()
%REGISTRY Initialize EEGflow operation registry.
% Usage:
%   reg = flow.Registry();                  % all ops

    reg = containers.Map('KeyType', 'char', 'ValueType', 'any');

    register_prep(reg);
    register_analysis(reg);

    % Optional aliases for LLM robustness (e.g., "prep.filter")
    keys = reg.keys();
    for i = 1:numel(keys)
        shortKey = keys{i};
        if ~isempty(strfind(shortKey, '.'))
            continue;
        end
        longKey = ['prep.' shortKey];
        if ~reg.isKey(longKey)
            reg(longKey) = reg(shortKey);
        end
        longKey = ['analysis.' shortKey];
        if ~reg.isKey(longKey)
            reg(longKey) = reg(shortKey);
        end
    end

    fprintf('Registry initialized with %d operations.\n', reg.Count);
end
