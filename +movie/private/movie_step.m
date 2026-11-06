function state = movie_step(state, args, meta, op)
%MOVIE_STEP Thin pipeline adapter; algorithms retain their direct interfaces.
    % Validation does not load files or execute numerical/graphics routines.
    if meta.validate_only
        return;
    end
    if ismember(op, {'compute_isc', 'test_isc'})
        component = 1;
        if isfield(args, 'component')
            component = args.component;
            args = rmfield(args, 'component');
        end
        validateattributes(component, {'numeric'}, {'scalar','integer','positive'});
        projected = state.movie.corrca.Y;
        Y = reshape(projected(:,component,:), size(projected,1), size(projected,3));
    end
    names = fieldnames(args);
    values = struct2cell(args);
    nv = reshape([names.'; values.'], 1, []);

    switch op
        case 'collect_segments'
            state.movie.data = movie.collect_segments(nv{:});
        case 'qc_files'
            [metrics, flags] = movie.qc_files(nv{:});
            state.movie.qc.files.metrics = metrics;
            state.movie.qc.files.flags = flags;
        case 'qc_filter'
            state.movie.data = movie.qc_filter(state.movie.data, nv{:});
        case 'qc_lengths'
            p = inputParser;
            addParameter(p, 'tolerance_sec', 1, @isscalar);
            parse(p, nv{:});
            data = state.movie.data;
            subjects = fieldnames(data);
            subjects = subjects(startsWith(subjects, 'sub_'));
            if isfield(data.meta, 'tfr') && data.meta.tfr.enable
                counts = cellfun(@(s) data.(s).tfr_input_samples, subjects);
            else
                counts = cellfun(@(s) size(data.(s).data, 2), subjects);
            end
            [valid, keep, target, report] = movie.qc_lengths(counts, data.meta.fs, p.Results.tolerance_sec);
            state.movie.qc.lengths = struct('subjects', {subjects}, ...
                'is_valid', valid, 'keep_idx', keep, 'target_len', target, 'report', report);
        case {'run_corrca', 'run_corrca_stream'}
            if strcmp(op, 'run_corrca')
                if isfield(args, 'fixed')
                    [W, ISC, Y, A, p] = movie.run_corrca(state.movie.data, nv{:});
                else
                    [W, ISC, Y, A] = movie.run_corrca(state.movie.data, nv{:});
                end
            else
                [W, ISC, Y, A] = movie.run_corrca_stream(nv{:});
            end
            state.movie.corrca = struct('W', W, 'ISC', ISC, 'Y', Y, 'A', A);
            if strcmp(op, 'run_corrca') && isfield(args, 'fixed')
                state.movie.corrca.p = p;
            end
        case 'compute_isc'
            [isc, info, pairwise] = movie.compute_isc(Y, nv{:});
            state.movie.isc = struct('values', isc, 'meta', info, ...
                'pairwise', pairwise, 'component', component);
        case 'test_isc'
            state.movie.isc_test = movie.test_isc(Y, nv{:});
        case 'plot_isc_test'
            movie.plot_isc_test(state.movie.isc_test, nv{:});
        case 'run_cp'
            state.movie.cp = movie.run_cp(state.movie.data, nv{:});
        case 'plot_cp'
            movie.plot_cp(state.movie.cp, nv{:});
    end
end
