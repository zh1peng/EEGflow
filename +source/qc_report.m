function out = qc_report(stateOrSource, varargin)
%QC_REPORT Write a compact source-space QC report.

    [args, meta] = local_parse_args(varargin{:});
    if ~isstruct(stateOrSource)
        error('source:qc_report:BadInput', 'Input must be a state or source struct.');
    end
    if isfield(meta, 'validate_only') && meta.validate_only
        out = stateOrSource;
        return;
    end
    if ~isfield(args, 'OutputFile'), args.OutputFile = ''; end

    report = local_collect(stateOrSource);
    outFile = char(string(args.OutputFile));
    if ~isempty(outFile)
        [outDir, ~, ~] = fileparts(outFile);
        if ~isempty(outDir) && ~isfolder(outDir), mkdir(outDir); end
        fid = fopen(outFile, 'w');
        if fid < 0
            error('source:qc_report:CannotWrite', 'Cannot write report: %s', outFile);
        end
        cleaner = onCleanup(@() fclose(fid));
        fprintf(fid, '# EEGflow Source QC\n\n');
        local_write_struct(fid, report, '');
        clear cleaner;
    end

    if isfield(stateOrSource, 'source')
        out = stateOrSource;
        if ~isfield(out.source, 'qc') || ~isstruct(out.source.qc)
            out.source.qc = struct();
        end
        out.source.qc.report = report;
        if ~isempty(outFile)
            out.source.qc.report_file = outFile;
        end
    else
        out = report;
    end
end

function [args, meta] = local_parse_args(varargin)
    args = struct();
    meta = struct();
    if isempty(varargin)
        return;
    end
    if isstruct(varargin{1})
        args = varargin{1};
        if numel(varargin) >= 2 && isstruct(varargin{2})
            meta = varargin{2};
        end
        return;
    end
    if mod(numel(varargin), 2) ~= 0
        error('source:qc_report:BadArgs', 'Use args struct or name-value pairs.');
    end
    for i = 1:2:numel(varargin)
        args.(char(string(varargin{i}))) = varargin{i+1};
    end
end

function report = local_collect(x)
    report = struct();
    if isfield(x, 'source') && isstruct(x.source)
        if isfield(x.source, 'qc'), report.qc = x.source.qc; end
        if isfield(x.source, 'epochs')
            report.epochs = local_epoch_summary(x.source.epochs);
        end
        return;
    end
    report.epochs = local_epoch_summary(x);
end

function s = local_epoch_summary(src)
    s = struct();
    s.level = local_get(src, 'level', '');
    s.n_signal = numel(local_get(src, 'label', {}));
    s.n_trial = numel(local_get(src, 'trial', {}));
    if isfield(src, 'trial') && ~isempty(src.trial)
        s.n_time = size(src.trial{1}, 2);
        vars = nan(s.n_signal, s.n_trial);
        allFinite = true;
        for t = 1:s.n_trial
            X = double(src.trial{t});
            allFinite = allFinite && all(isfinite(X(:)));
            vars(:, t) = var(X, 0, 2, 'omitnan');
        end
        s.all_finite = allFinite;
        s.variance_median = median(vars(:), 'omitnan');
        s.variance_p95 = prctile(vars(:), 95);
    end
    if isfield(src, 'parcellation')
        s.has_parcellation = true;
    end
end

function local_write_struct(fid, s, prefix)
    names = fieldnames(s);
    for i = 1:numel(names)
        name = names{i};
        value = s.(name);
        key = name;
        if ~isempty(prefix), key = [prefix '.' name]; end
        if isstruct(value)
            local_write_struct(fid, value, key);
        elseif isnumeric(value) || islogical(value)
            if isscalar(value)
                fprintf(fid, '- %s: %g\n', key, value);
            else
                fprintf(fid, '- %s: [%s]\n', key, num2str(size(value)));
            end
        elseif ischar(value) || isstring(value)
            fprintf(fid, '- %s: %s\n', key, char(string(value)));
        elseif iscell(value)
            fprintf(fid, '- %s: %d item(s)\n', key, numel(value));
        end
    end
end

function v = local_get(s, field, default)
    v = default;
    if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
        v = s.(field);
    end
end
