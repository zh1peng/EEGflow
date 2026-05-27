function state = erp_compute_source_contrast(state, args, meta)
%ERP_COMPUTE_SOURCE_CONTRAST Compute a condition difference for source ERPs.

    if nargin < 2 || isempty(args), args = struct(); end
    if nargin < 3, meta = struct(); end
    if ~isfield(args, 'Name') || isempty(args.Name), args.Name = 'source_contrast'; end
    if ~isfield(args, 'PositiveCondition') || ~isfield(args, 'NegativeCondition')
        error('analysis:erp_compute_source_contrast:MissingCondition', ...
            'PositiveCondition and NegativeCondition are required.');
    end

    if isfield(meta, 'validate_only') && meta.validate_only
        return;
    end
    if ~isfield(state, 'source') || ~isfield(state.source, 'erp')
        error('analysis:erp_compute_source_contrast:MissingERP', ...
            'Run analysis.erp_compute_source_erps first.');
    end

    erp = state.source.erp;
    pos = local_condition(erp, args.PositiveCondition);
    neg = local_condition(erp, args.NegativeCondition);

    c = struct();
    c.waveform = pos.avg - neg.avg;
    c.positive_condition = char(string(args.PositiveCondition));
    c.negative_condition = char(string(args.NegativeCondition));
    c.label = erp.label;
    c.time = erp.time;
    c.level = erp.level;
    if isfield(erp, 'source_pos'), c.source_pos = erp.source_pos; end
    if isfield(erp, 'parcellation'), c.parcellation = erp.parcellation; end

    if ~isfield(state, 'erp_source') || ~isstruct(state.erp_source)
        state.erp_source = struct();
    end
    if ~isfield(state.erp_source, 'contrasts') || ~isstruct(state.erp_source.contrasts)
        state.erp_source.contrasts = struct();
    end
    state.erp_source.contrasts.(matlab.lang.makeValidName(args.Name)) = c;
end

function c = local_condition(erp, name)
    f = matlab.lang.makeValidName(char(string(name)));
    if ~isfield(erp.conditions, f)
        error('analysis:erp_compute_source_contrast:UnknownCondition', ...
            'Condition not found: %s.', char(string(name)));
    end
    c = erp.conditions.(f);
end
