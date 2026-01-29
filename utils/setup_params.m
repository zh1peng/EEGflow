function ParamsOut = setup_params(Params, varargin)
%SETUP_PARAMS Add LogFile/LogPath to selected subfields and set Output.filename.
%
% Usage:
%   ParamsOut = setup_params(Params);
%   ParamsOut = setup_params(Params, 'Suffix', '_cleaned');
%
% Name-Value options:
%   'Suffix'          : String appended to Input.filename to form Output.filename (default: '_prep')
%   'LogFileTargets'  : Cellstr of subfields to receive a .LogFile (default: all struct subfields)
%   'LogPathTargets'  : Cellstr of subfields to receive a .LogPath (default: {'BadChan','BadIC'})
%   'CreateIfMissing' : If true, create missing target subfields as struct (default: false)
%   'PerFieldLog'     : If true, each target gets its own log file (default: false)
%
% Effects:
%   - Ensures Output.filepath exists (mkdir if needed)
%   - Creates LogPath = <Output.filepath>\<basename>
%   - Creates LogFile = <Output.filepath>\<basename>.log
%   - Adds ParamsOut.error_LogFile and ParamsOut.basename
%   - Deletes any existing log files so runs start fresh

    p = inputParser;
    p.addParameter('Suffix', '_prep', @(x)ischar(x) || isstring(x));
    p.addParameter('LogFileTargets', [], @(x)iscellstr(x) || isempty(x));
    p.addParameter('LogPathTargets', {'BadChan','BadIC'}, @(x)iscellstr(x));
    p.addParameter('CreateIfMissing', false, @(x)islogical(x) && isscalar(x));
    p.addParameter('PerFieldLog', false, @(x)islogical(x) && isscalar(x));
    p.parse(varargin{:});

    suffix          = char(p.Results.Suffix);
    logFileTargets  = p.Results.LogFileTargets;
    logPathTargets  = p.Results.LogPathTargets;
    createMissing   = p.Results.CreateIfMissing;
    perFieldLog     = p.Results.PerFieldLog;

    ParamsOut = Params;  % work on a copy

    % --- Ensure Output.filepath exists ---
    if ~isfield(ParamsOut,'Output') || ~isstruct(ParamsOut.Output)
        ParamsOut.Output = struct();
    end
    if ~isfield(ParamsOut.Output,'filepath') || isempty(ParamsOut.Output.filepath)
        ParamsOut.Output.filepath = pwd;
    end
    outDir = ParamsOut.Output.filepath;
    if ~exist(outDir,'dir'), mkdir(outDir); end

    % --- Parse filenames ---
    inFile = '';
    if isfield(ParamsOut,'Input') && isfield(ParamsOut.Input,'filename') && ~isempty(ParamsOut.Input.filename)
        inFile = ParamsOut.Input.filename;
    end
    [~, baseName, inExt] = fileparts(inFile);
    if isempty(baseName)
        baseName = 'unnamed';
        if isempty(inExt), inExt = '.set'; end
    end

    % --- Final output filename ---
    ParamsOut.Output.filename = [baseName suffix inExt];
    ParamsOut.basename        = [baseName suffix];

    % --- Define LogFile + error_LogFile ---
    logFile       = fullfile(outDir, [ParamsOut.basename '.log']);
    errorLogFile  = fullfile(outDir, [ParamsOut.basename '_error.log']);

    % Delete old logs
    if exist(logFile,'file'), delete(logFile); end
    if exist(errorLogFile,'file'), delete(errorLogFile); end

    ParamsOut.LogFile       = logFile;
    ParamsOut.error_LogFile = errorLogFile;

    % --- Define LogPath directory ---
    logPathDir = fullfile(outDir, ParamsOut.basename);
    if ~exist(logPathDir,'dir'), mkdir(logPathDir); end

    % --- Default LogFileTargets: all struct subfields ---
    if isempty(logFileTargets)
        fns = fieldnames(ParamsOut);
        isStruct = cellfun(@(f) isstruct(ParamsOut.(f)), fns);
        logFileTargets = fns(isStruct);
    end

    % --- Assign LogFile to targets ---
    for i = 1:numel(logFileTargets)
        fld = logFileTargets{i};
        if isfield(ParamsOut, fld)
            if ~isstruct(ParamsOut.(fld))
                if createMissing
                    ParamsOut.(fld) = struct();
                else
                    continue;
                end
            end
        else
            if createMissing
                ParamsOut.(fld) = struct();
            else
                continue;
            end
        end

        if perFieldLog
            logFileName = sprintf('%s_%s.log', ParamsOut.basename, fld);
            ParamsOut.(fld).LogFile = fullfile(outDir, logFileName);
            if exist(ParamsOut.(fld).LogFile,'file')
                delete(ParamsOut.(fld).LogFile);
            end
        else
            ParamsOut.(fld).LogFile = logFile;
        end
    end

    % --- Assign LogPath to selected targets ---
    for i = 1:numel(logPathTargets)
        fld = logPathTargets{i};
        if isfield(ParamsOut, fld)
            if ~isstruct(ParamsOut.(fld))
                if createMissing
                    ParamsOut.(fld) = struct();
                else
                    continue;
                end
            end
            ParamsOut.(fld).LogPath = logPathDir;
        else
            if createMissing
                ParamsOut.(fld) = struct('LogPath', logPathDir);
            end
        end
    end
end
