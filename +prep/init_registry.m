function reg = init_registry()
%INIT_REGISTRY Initialize the operation registry for the EEG Pipeline
% Returns:
%   reg: containers.Map (char -> function_handle)

    % 1. Create Map
    reg = containers.Map('KeyType', 'char', 'ValueType', 'any');

    % 2. Define Layout: 'OpName' -> @WrapperFunction
    % Note: Wrapper functions are in the +prep package

    % --- I/O Operations ---
    register(reg, 'load_set',            @prep.load_set);
    register(reg, 'load_mff',            @prep.load_mff);
    register(reg, 'save_set',            @prep.save_set);

    % --- Preprocessing Operations ---
    register(reg, 'select_channels',     @prep.select_channels);
    register(reg, 'remove_channels',     @prep.remove_channels);
    register(reg, 'downsample',          @prep.downsample);
    register(reg, 'filter',              @prep.filter);
    register(reg, 'remove_powerline',    @prep.remove_powerline);
    register(reg, 'crop_by_markers',     @prep.crop_by_markers);
    register(reg, 'insert_relative_markers', @prep.insert_relative_markers);
    register(reg, 'correct_baseline',    @prep.correct_baseline);
    register(reg, 'remove_bad_channels', @prep.remove_bad_channels);
    register(reg, 'interpolate',         @prep.interpolate);
    register(reg, 'interpolate_bad_channels_epoch', @prep.interpolate_bad_channels_epoch);
    register(reg, 'reref',               @prep.reref);
    register(reg, 'remove_bad_epoch',    @prep.remove_bad_epoch);
    register(reg, 'remove_bad_ICs',      @prep.remove_bad_ICs);
    register(reg, 'segment_task',        @prep.segment_task);
    register(reg, 'segment_rest',        @prep.segment_rest);

    % 3. (Optional) Register Aliases for LLM robustness
    % LLM sometimes hallucinates "prep.filter" instead of just "filter"
    keys = reg.keys();
    for i = 1:numel(keys)
        shortKey = keys{i};
        longKey  = ['prep.' shortKey]; % e.g. "prep.filter"
        if ~reg.isKey(longKey)
            reg(longKey) = reg(shortKey);
        end
    end

    fprintf('Registry initialized with %d operations.\n', reg.Count);
end

function register(reg, op, fn)
    % Helper to register and validate
    if ~isa(fn, 'function_handle')
        error('Registry:BadHandle', 'Value for %s must be a function_handle.', op);
    end
    reg(op) = fn;
end
