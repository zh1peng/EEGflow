function [pipe, state, cfg] = build_pipeline(cfgIn, varargin)
%BUILD_PIPELINE Build a movie workflow using flow.Pipeline.
%   [pipe,state,cfg] = movie.build_pipeline(cfgOrJson, 'State', state)
%   Results are stored in state.movie; numerical functions also work directly.

    p = inputParser;
    addParameter(p, 'State', struct(), @isstruct);
    parse(p, varargin{:});
    if ischar(cfgIn) || isstring(cfgIn)
        cfg = flow.load_cfg(cfgIn);
    else
        cfg = cfgIn;
    end
    steps = cfg.steps;
    for i = 1:numel(steps)
        if isfield(steps(i), 'args_ref') && ~isempty(steps(i).args_ref) && ...
                (~isfield(steps(i), 'args') || isempty(steps(i).args))
            steps(i).args = cfg.(steps(i).args_ref);
        end
    end
    state = p.Results.State;
    state.cfg = cfg;
    pipe = flow.Pipeline(state, init_registry());
    pipe.add_steps(struct('steps', steps));
end
