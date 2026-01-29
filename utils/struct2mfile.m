function struct2mfile(S, rootName, filename)
% STRUCT2MFILE  Dump a (possibly nested) struct to a .m script.
%
%   struct2mfile(Params, 'Params', 'Params_config.m');
%
% creates a file Params_config.m that, when run, recreates the struct
% variable Params with the same fields and values.
%
% Supported value types:
%   - numeric / logical arrays
%   - char strings
%   - string scalars
%   - cell arrays of the above
%   - nested structs (arbitrary depth)

    if nargin < 2 || isempty(rootName)
        rootName = inputname(1);
        if isempty(rootName), rootName = 'cfg'; end
    end
    if nargin < 3 || isempty(filename)
        filename = [rootName '_config.m'];
    end

    fid = fopen(filename, 'w');
    if fid == -1
        error('Cannot open %s for writing.', filename);
    end

    fprintf(fid, '%% Auto-generated config from struct "%s"\n', rootName);
    fprintf(fid, '%% Run this script to recreate the %s struct.\n\n', rootName);
    fprintf(fid, '%s = struct();\n\n', rootName);

    writeStruct(fid, S, rootName);
    fclose(fid);
end

function writeStruct(fid, s, prefix)
    flds = fieldnames(s);
    for i = 1:numel(flds)
        fn = flds{i};
        v  = s.(fn);
        path = sprintf('%s.%s', prefix, fn);

        if isstruct(v)
            % Recurse into nested struct
            fprintf(fid, '%% %s is a struct\n', path);
            fprintf(fid, '%s = struct();\n', path);
            writeStruct(fid, v, path);

        else
            code = value2code(v);
            if ~isempty(code)
                fprintf(fid, '%s = %s;\n', path, code);
            else
                fprintf(fid, '%% Skipped %s (unsupported type)\n', path);
            end
        end
        fprintf(fid, '\n');
    end
end

function code = value2code(v)
    % Convert a MATLAB value into literal code as a string.
    if isnumeric(v) || islogical(v)
        code = mat2str(v);          % handles scalars and arrays
    elseif ischar(v)
        code = ['''' strrep(v, '''', '''''') ''''];  % escape single quotes
    elseif isstring(v) && isscalar(v)
        s = char(v);
        code = ['''' strrep(s, '''', '''''') ''''];
    elseif iscell(v)
        try
            parts = cellfun(@value2code, v, 'UniformOutput', false);
            code  = ['{' strjoin(parts, ', ') '}'];
        catch
            code = '';
        end
    else
        code = '';   % unsupported type -> skip
    end
end
