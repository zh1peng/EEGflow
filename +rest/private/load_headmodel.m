function headmodel = load_headmodel(params, unit)
%LOAD_HEADMODEL Load a FieldTrip headmodel from params struct.
%
% Accepted inputs:
%   - params.HeadModel      : already-loaded headmodel struct
%   - params.HeadModelPath  : .mat file containing variable 'vol' or 'headmodel'
%
% unit (optional):
%   - convert to this unit using ft_convert_units when available.

    if nargin < 2 || isempty(unit)
        unit = '';
    end
    unit = char(string(unit));

    headmodel = [];
    if isstruct(params) && isfield(params, 'HeadModel') && ~isempty(params.HeadModel)
        headmodel = params.HeadModel;
    elseif isstruct(params) && isfield(params, 'HeadModelPath') && ~isempty(params.HeadModelPath)
        p = char(string(params.HeadModelPath));
        if exist(p, 'file') ~= 2
            error('rest:load_headmodel:HeadModelNotFound', 'HeadModelPath not found: %s', p);
        end
        S = load(p);
        if isfield(S, 'vol')
            headmodel = S.vol;
        elseif isfield(S, 'headmodel')
            headmodel = S.headmodel;
        else
            % last resort: single variable MAT
            f = fieldnames(S);
            if numel(f) == 1
                headmodel = S.(f{1});
            else
                error('rest:load_headmodel:BadHeadModelFile', 'Could not find headmodel in %s', p);
            end
        end
    else
        error('rest:load_headmodel:MissingHeadModel', 'Provide params.HeadModel or params.HeadModelPath.');
    end

    if exist('ft_convert_units', 'file') && ~isempty(unit)
        try
            headmodel = ft_convert_units(headmodel, unit);
        catch
            % best effort only
        end
    end
end

