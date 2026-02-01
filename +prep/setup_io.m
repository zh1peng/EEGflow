function cfgOut = setup_io(cfg, varargin)
%SETUP_IO Configure prep IO/log fields in a config struct.
%
% Usage:
%   cfgOut = prep.setup_io(cfg, 'InputPath', inPath, 'InputFilename', inFile, 'OutputPath', outPath);
%   cfgOut = prep.setup_io(cfg, 'InputPath', inPath, 'InputFilename', inFile, 'OutputPath', outPath, ...
%       'Suffix', '_cleaned');
%
% This helper is designed for prep configs (cfg). It:
%   - sets cfg.Output.filename based on Input.filename
%   - adds LogFile/LogPath to selected cfg subfields
%   - creates output/log directories as needed
%
% Name-Value options:
%   'InputPath'         : Folder containing raw input data (default: '')
%   'InputFilename'     : Input filename (may be full path; default: '')
%   'OutputPath'        : Folder for outputs/logs (default: '')
%   'Suffix'             : String appended to Input.filename (default: '_prep')
%   'OutputBaseName'     : Override basename for Output.filename/logs (default: '')
%   'LogFileTargets'     : Cellstr of subfields to receive .LogFile (default: all struct subfields)
%   'LogPathTargets'     : Cellstr of subfields to receive .LogPath (default: {'BadChan','BadIC'})
%   'CreateIfMissing'    : Create missing target subfields as struct (default: false)
%   'PerFieldLog'        : Each target gets its own log file (default: false)
%   'DeleteExistingLogs' : If true, delete existing log files (default: false)
%
% Effects:
%   - Ensures Output.filepath exists (mkdir if needed)
%   - Creates LogPath = <Output.filepath>\<basename>
%   - Creates LogFile = <Output.filepath>\<basename>.log
%   - Adds cfgOut.LogFile, cfgOut.error_LogFile, cfgOut.basename
%
% Notes:
%   - If cfg.Output.basename is set and OutputBaseName is empty, it will be used.

    p = inputParser;
    p.addParameter('InputPath', '', @(x)ischar(x) || isstring(x));
    p.addParameter('InputFilename', '', @(x)ischar(x) || isstring(x));
    p.addParameter('OutputPath', '', @(x)ischar(x) || isstring(x));
    p.addParameter('Suffix', '_prep', @(x)ischar(x) || isstring(x));
    p.addParameter('OutputBaseName', '', @(x)ischar(x) || isstring(x));
    p.addParameter('LogFileTargets', [], @(x)iscellstr(x) || isempty(x));
    p.addParameter('LogPathTargets', {'BadChan','BadIC'}, @(x)iscellstr(x));
    p.addParameter('CreateIfMissing', false, @(x)islogical(x) && isscalar(x));
    p.addParameter('PerFieldLog', false, @(x)islogical(x) && isscalar(x));
    p.addParameter('DeleteExistingLogs', true, @(x)islogical(x) && isscalar(x));
    p.parse(varargin{:});

    inputPath       = char(p.Results.InputPath);
    inputFilename   = char(p.Results.InputFilename);
    outputPath      = char(p.Results.OutputPath);
    suffix          = char(p.Results.Suffix);
    outputBaseName  = char(p.Results.OutputBaseName);
    logFileTargets  = p.Results.LogFileTargets;
    logPathTargets  = p.Results.LogPathTargets;
    createMissing   = p.Results.CreateIfMissing;
    perFieldLog     = p.Results.PerFieldLog;
    deleteExisting  = p.Results.DeleteExistingLogs;

    cfgOut = cfg;  % work on a copy

    % --- Input/Output fields ---
    if ~isfield(cfgOut,'Input') || ~isstruct(cfgOut.Input)
        cfgOut.Input = struct();
    end
    if ~isempty(inputPath)
        cfgOut.Input.filepath = inputPath;
    elseif ~isfield(cfgOut.Input,'filepath')
        cfgOut.Input.filepath = '';
    end

    if ~isempty(inputFilename)
        cfgOut.Input.filename = inputFilename;
    elseif ~isfield(cfgOut.Input,'filename')
        cfgOut.Input.filename = '';
    end

    if ~isfield(cfgOut,'Output') || ~isstruct(cfgOut.Output)
        cfgOut.Output = struct();
    end
    if ~isempty(outputPath)
        cfgOut.Output.filepath = outputPath;
    elseif ~isfield(cfgOut.Output,'filepath') || isempty(cfgOut.Output.filepath)
        cfgOut.Output.filepath = pwd;
    end

    outDir = cfgOut.Output.filepath;
    if ~exist(outDir,'dir'), mkdir(outDir); end

    % --- Parse input filename (full path is allowed) ---
    inFile = '';
    if isfield(cfgOut,'Input') && isfield(cfgOut.Input,'filename') && ~isempty(cfgOut.Input.filename)
        inFile = cfgOut.Input.filename;
    end
    [~, baseName, inExt] = fileparts(inFile);
    if isempty(baseName)
        baseName = 'unnamed';
        if isempty(inExt), inExt = '.set'; end
    end

    % Allow Output.basename override (or explicit OutputBaseName)
    if ~isempty(outputBaseName)
        baseName = outputBaseName;
    elseif isfield(cfgOut.Output,'basename') && ~isempty(cfgOut.Output.basename)
        baseName = cfgOut.Output.basename;
    end

    % --- Final output filename ---
    cfgOut.Output.filename = [baseName suffix inExt];
    cfgOut.Output.basename = baseName;
    cfgOut.basename        = [baseName suffix];

    % --- Define LogFile + error_LogFile ---
    logFile      = fullfile(outDir, [cfgOut.basename '.log']);
    errorLogFile = fullfile(outDir, [cfgOut.basename '_error.log']);

    % Delete old logs (optional)
    if deleteExisting
        if exist(logFile,'file'), delete(logFile); end
        if exist(errorLogFile,'file'), delete(errorLogFile); end
    end

    cfgOut.LogFile       = logFile;
    cfgOut.error_LogFile = errorLogFile;

    % --- Define LogPath directory ---
    logPathDir = fullfile(outDir, cfgOut.basename);
    if ~exist(logPathDir,'dir'), mkdir(logPathDir); end

    % --- Default LogFileTargets: struct subfields, excluding config/meta blocks ---
    if isempty(logFileTargets)
        fns = fieldnames(cfgOut);
        isStruct = cellfun(@(f) isstruct(cfgOut.(f)), fns);
        skip = {'steps','spec','Options','params','Input','Output'};
        keep = isStruct & ~ismember(fns, skip);
        logFileTargets = fns(keep);
    end

    % --- Assign LogFile to targets ---
    for i = 1:numel(logFileTargets)
        fld = logFileTargets{i};
        if isfield(cfgOut, fld)
            if ~isstruct(cfgOut.(fld))
                if createMissing
                    cfgOut.(fld) = struct();
                else
                    continue;
                end
            end
        else
            if createMissing
                cfgOut.(fld) = struct();
            else
                continue;
            end
        end

        if perFieldLog
            logFileName = sprintf('%s_%s.log', cfgOut.basename, fld);
            cfgOut.(fld).LogFile = fullfile(outDir, logFileName);
            if deleteExisting && exist(cfgOut.(fld).LogFile,'file')
                delete(cfgOut.(fld).LogFile);
            end
        else
            cfgOut.(fld).LogFile = logFile;
        end
    end

    % --- Assign LogPath to selected targets ---
    for i = 1:numel(logPathTargets)
        fld = logPathTargets{i};
        if isfield(cfgOut, fld)
            if ~isstruct(cfgOut.(fld))
                if createMissing
                    cfgOut.(fld) = struct();
                else
                    continue;
                end
            end
            cfgOut.(fld).LogPath = logPathDir;
        else
            if createMissing
                cfgOut.(fld) = struct('LogPath', logPathDir);
            end
        end
    end

    % --- Populate step args based on op requirements ---
    if isfield(cfgOut, 'steps') && isstruct(cfgOut.steps)
        ops_need_logfile = { ...
            'load_set','load_mff','save_set','downsample','filter','remove_powerline', ...
            'crop_by_markers','remove_bad_channels','remove_bad_ICs','remove_channels', ...
            'reref','correct_baseline','interpolate','interpolate_bad_channels_epoch', ...
            'remove_bad_epoch','select_channels','segment_rest','segment_task','insert_relative_markers', ...
            'edit_chantype'};
        ops_need_logpath = {'remove_bad_channels','remove_bad_ICs'};
        ops_need_infile  = {'load_set','load_mff'};
        ops_need_outfile = {'save_set'};

        for i = 1:numel(cfgOut.steps)
            if ~isfield(cfgOut.steps(i), 'args') || ~isstruct(cfgOut.steps(i).args)
                cfgOut.steps(i).args = struct();
            end
            args = cfgOut.steps(i).args;
            op = '';
            if isfield(cfgOut.steps(i), 'op') && ischar(cfgOut.steps(i).op)
                op = lower(cfgOut.steps(i).op);
            end

            if ismember(op, ops_need_infile)
                if ~isfield(args, 'filename') || isempty(args.filename)
                    args.filename = cfgOut.Input.filename;
                end
                if ~isfield(args, 'filepath') || isempty(args.filepath)
                    args.filepath = cfgOut.Input.filepath;
                end
            end

            if ismember(op, ops_need_outfile)
                if ~isfield(args, 'filename') || isempty(args.filename)
                    args.filename = cfgOut.Output.filename;
                end
                if ~isfield(args, 'filepath') || isempty(args.filepath)
                    args.filepath = cfgOut.Output.filepath;
                end
            end

            if ismember(op, ops_need_logfile)
                if ~isfield(args, 'LogFile') || isempty(args.LogFile)
                    args.LogFile = cfgOut.LogFile;
                end
            end

            if ismember(op, ops_need_logpath)
                if ~isfield(args, 'LogPath') || isempty(args.LogPath)
                    args.LogPath = logPathDir;
                end
            end

            % normalize common label fields to cellstr
            labelFields = {'ExcludeLabel','Chan2remove','KnownBadLabel','EOGLabel','ECGLabel','OtherLabel','Markers'};
            for k = 1:numel(labelFields)
                f = labelFields{k};
                if isfield(args, f)
                    args.(f) = local_to_cellstr(args.(f));
                end
            end

            cfgOut.steps(i).args = args;
        end
    end
end

function out = local_to_char(x)
    if isstring(x), out = char(x); return; end
    if isnumeric(x), out = num2str(x); return; end
    out = x;
end

function out = local_to_cellstr(x)
    if isempty(x), out = {}; return; end
    if ischar(x), out = {x}; return; end
    if isstring(x), out = cellstr(x); return; end
    if iscell(x)
        out = cellfun(@local_to_char, x, 'UniformOutput', false);
        return;
    end
    out = x;
end
