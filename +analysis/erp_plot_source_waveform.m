function fig = erp_plot_source_waveform(state, args, meta)
%ERP_PLOT_SOURCE_WAVEFORM Plot parcel/source ERP waveforms.

    if nargin < 2 || isempty(args), args = struct(); end
    if nargin < 3, meta = struct(); end
    if isfield(meta, 'validate_only') && meta.validate_only, fig = []; return; end
    if ~isfield(state, 'erp_source') || ~isfield(state.erp_source, 'erps')
        error('analysis:erp_plot_source_waveform:MissingERP', ...
            'Run analysis.erp_compute_source_erps first.');
    end

    if ~isfield(args, 'Condition') || isempty(args.Condition), args.Condition = ''; end
    if ~isfield(args, 'Signals'), args.Signals = []; end
    if ~isfield(args, 'Visible'), args.Visible = 'off'; end
    if ~isfield(args, 'OutputFile'), args.OutputFile = ''; end

    erp = state.erp_source.erps;
    condName = char(string(args.Condition));
    if isempty(condName)
        names = fieldnames(erp.conditions);
        if numel(names) ~= 1
            error('analysis:erp_plot_source_waveform:MissingCondition', ...
                'Specify Condition when multiple source ERP conditions exist.');
        end
        condName = names{1};
    end
    f = matlab.lang.makeValidName(condName);
    if ~isfield(erp.conditions, f)
        error('analysis:erp_plot_source_waveform:UnknownCondition', 'Condition not found: %s.', condName);
    end

    src = struct();
    src.label = erp.label;
    src.trial = {erp.conditions.(f).avg};
    src.time = {erp.time};
    src.fsample = erp.fsample;
    src.level = erp.level;
    fig = source.plot_source_timeseries(src, ...
        'Signals', args.Signals, ...
        'Visible', args.Visible, ...
        'OutputFile', args.OutputFile);
end
