function reg = init_registry()
%INIT_REGISTRY Adapt movie workflows to the state + args + meta contract.
    reg = containers.Map('KeyType', 'char', 'ValueType', 'any');
    ops = {'collect_segments', 'qc_files', 'qc_filter', 'qc_lengths', ...
        'run_corrca', 'run_corrca_stream', 'compute_isc', 'test_isc', ...
        'plot_isc_test', 'run_cp', 'plot_cp'};
    for i = 1:numel(ops)
        op = ops{i};
        reg(op) = @(state,args,meta) movie_step(state,args,meta,op);
    end
end
