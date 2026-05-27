function fig = tf_plot_source(state, args, meta)
%TF_PLOT_SOURCE Plot source/parcel time-frequency power for one signal.

    if nargin < 2 || isempty(args), args = struct(); end
    if nargin < 3, meta = struct(); end
    if isfield(meta, 'validate_only') && meta.validate_only, fig = []; return; end
    if ~isfield(state, 'tf_source') || ~isfield(state.tf_source, 'power')
        error('analysis:tf_plot_source:MissingTF', 'Run analysis.tf_compute_source first.');
    end

    if ~isfield(args, 'Condition'), args.Condition = ''; end
    if ~isfield(args, 'Signal'), args.Signal = 1; end
    if ~isfield(args, 'Visible'), args.Visible = 'off'; end
    if ~isfield(args, 'OutputFile'), args.OutputFile = ''; end

    tf = state.tf_source.power;
    cond = char(string(args.Condition));
    if isempty(cond)
        names = fieldnames(tf.conditions);
        if numel(names) ~= 1
            error('analysis:tf_plot_source:MissingCondition', ...
                'Specify Condition when multiple source TF conditions exist.');
        end
        cond = names{1};
    end
    f = matlab.lang.makeValidName(cond);
    if ~isfield(tf.conditions, f)
        error('analysis:tf_plot_source:UnknownCondition', 'Condition not found: %s.', cond);
    end

    sig = local_signal_index(tf, args.Signal);
    c = tf.conditions.(f);
    fig = figure('Visible', char(string(args.Visible)), 'Color', 'w');
    imagesc(c.times, c.freqs, squeeze(c.power(sig, :, :)));
    axis xy;
    xlabel('Time (s)');
    ylabel('Frequency (Hz)');
    title(sprintf('%s: %s', c.label, tf.label{sig}), 'Interpreter', 'none');
    colorbar;
    colormap(parula);

    outFile = char(string(args.OutputFile));
    if ~isempty(outFile)
        [outDir, ~, ~] = fileparts(outFile);
        if ~isempty(outDir) && ~isfolder(outDir), mkdir(outDir); end
        exportgraphics(fig, outFile, 'Resolution', 150);
    end
end

function idx = local_signal_index(tf, signal)
    if isnumeric(signal)
        idx = round(signal(1));
    else
        [tfFound, idx] = ismember(string(signal), string(tf.label));
        if ~tfFound, idx = 0; end
    end
    if idx < 1 || idx > numel(tf.label)
        error('analysis:tf_plot_source:BadSignal', 'Signal not found.');
    end
end
