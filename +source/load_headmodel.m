function headmodel = load_headmodel(params, unit)
%LOAD_HEADMODEL Resolve and load a FieldTrip headmodel.

    if nargin < 1 || isempty(params), params = struct(); end
    if nargin < 2 || isempty(unit)
        unit = '';
        if isstruct(params) && isfield(params, 'Unit') && ~isempty(params.Unit)
            unit = params.Unit;
        end
    end
    unit = char(string(unit));

    if isstruct(params) && isfield(params, 'HeadModel') && ~isempty(params.HeadModel)
        headmodel = params.HeadModel;
    elseif isstruct(params) && isfield(params, 'HeadModelPath') && ~isempty(params.HeadModelPath)
        headmodel = local_load_file(char(string(params.HeadModelPath)));
    elseif isstruct(params) && isfield(params, 'HeadModelTemplate') && ~isempty(params.HeadModelTemplate)
        headmodel = local_load_file(source.headmodel_default_path(params.HeadModelTemplate));
    else
        error('source:load_headmodel:MissingHeadModel', ...
            'Provide HeadModel, HeadModelPath, or HeadModelTemplate.');
    end

    if exist('ft_convert_units', 'file') == 2 && ~isempty(unit)
        try
            headmodel = ft_convert_units(headmodel, unit);
        catch
        end
    end
end

function headmodel = local_load_file(p)
    if exist(p, 'file') ~= 2
        error('source:load_headmodel:HeadModelNotFound', 'HeadModelPath not found: %s', p);
    end
    S = load(p);
    if isfield(S, 'vol')
        headmodel = S.vol;
    elseif isfield(S, 'headmodel')
        headmodel = S.headmodel;
    else
        f = fieldnames(S);
        if numel(f) ~= 1
            error('source:load_headmodel:BadHeadModelFile', 'Could not find headmodel in %s', p);
        end
        headmodel = S.(f{1});
    end
end
