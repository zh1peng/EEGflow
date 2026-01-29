function reg = init_registry()
%INIT_REGISTRY Initialize the analysis operation registry for ERP pipeline
% Returns:
%   reg: containers.Map (char -> function_handle)

    % 1. Create Map
    reg = containers.Map('KeyType', 'char', 'ValueType', 'any');

    % 2. Analysis Operations (context wrappers)
    register(reg, 'define_group',      @analysis.define_group);
    register(reg, 'select_conditions', @analysis.select_conditions);
    register(reg, 'compute_erps',      @analysis.compute_erps);
    register(reg, 'compute_ga',        @analysis.compute_ga);
    register(reg, 'compute_stats',     @analysis.compute_stats);
    register(reg, 'plot_erp',          @analysis.plot_erp);

    % 3. (Optional) Register Aliases for LLM robustness
    keys = reg.keys();
    for i = 1:numel(keys)
        shortKey = keys{i};
        longKey  = ['analysis.' shortKey];
        if ~reg.isKey(longKey)
            reg(longKey) = reg(shortKey);
        end
    end

    fprintf('Analysis registry initialized with %d operations.\n', reg.Count);
end

function register(reg, op, fn)
    % Helper to register and validate
    if ~isa(fn, 'function_handle')
        error('Registry:BadHandle', 'Value for %s must be a function_handle.', op);
    end
    reg(op) = fn;
end
