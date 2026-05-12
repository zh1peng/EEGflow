function state = tf_plot(state, args, meta)
    % Args: target, group (opt), condition (opt), x_range, freq_range, color_range, mask
    if ~isfield(args, 'group'), args.group = ''; end
    if ~isfield(args, 'condition'), args.condition = ''; end

    if nargin >= 3 && isfield(meta, 'validate_only') && meta.validate_only
        return;
    end

    state_check(state, 'GA_TFD');
    [ch_idx, title_str] = state_get_indices(state, args.target);

    groups = fieldnames(state.Results.GA_TFD);
    if ~isempty(args.group), groups = {args.group}; end

    [freqs, times] = state_get_tf_axes(state, state.Selection.Groups.(groups{1}), state.Selection.Conditions{1});

    for g = 1:numel(groups)
        gn = groups{g};
        conds = fieldnames(state.Results.GA_TFD.(gn));
        if ~isempty(args.condition), conds = {args.condition}; end

        figure('Name', ['TFR ' gn]);
        for c = 1:numel(conds)
            cn = conds{c};
            subplot(1, numel(conds), c);

            data = state.Results.GA_TFD.(gn).(cn).tfd;
            plot_data = squeeze(mean(data(ch_idx, :, :), 1));

            state_imagesc_tfr(times, freqs, plot_data, args);
            title(sprintf('%s - %s\n%s', gn, cn, title_str), 'Interpreter', 'none');
        end
    end
end
