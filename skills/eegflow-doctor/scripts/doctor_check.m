function report = doctor_check(varargin)
%DOCTOR_CHECK EEGflow environment check (MATLAB).
%
% Usage:
%   report = doctor_check();
%   report = doctor_check('EEGLAB_ROOT','C:\toolboxes\eeglab2023.1','AddPath',true);
%
% Name-Value:
%   EEGFLOW_ROOT, EEGLAB_ROOT, FASTER_ROOT, ICLABEL_ROOT, CLEANLINE_ROOT
%   AddPath (false)  - add paths for provided roots
%   SavePath (false) - call savepath after AddPath

    p = inputParser;
    p.addParameter('EEGFLOW_ROOT', getenv('EEGFLOW_ROOT'), @(s)ischar(s) || isstring(s));
    p.addParameter('EEGLAB_ROOT', getenv('EEGLAB_ROOT'), @(s)ischar(s) || isstring(s));
    p.addParameter('FASTER_ROOT', getenv('FASTER_ROOT'), @(s)ischar(s) || isstring(s));
    p.addParameter('ICLABEL_ROOT', getenv('ICLABEL_ROOT'), @(s)ischar(s) || isstring(s));
    p.addParameter('CLEANLINE_ROOT', getenv('CLEANLINE_ROOT'), @(s)ischar(s) || isstring(s));
    p.addParameter('AddPath', false, @(x)islogical(x) && isscalar(x));
    p.addParameter('SavePath', false, @(x)islogical(x) && isscalar(x));
    p.parse(varargin{:});
    opt = p.Results;

    report = struct();
    report.env = opt;
    report.missing = {};

    if opt.AddPath
        add_if_dir(opt.EEGFLOW_ROOT);
        add_if_dir(opt.EEGLAB_ROOT);
        add_if_dir(opt.FASTER_ROOT);
        add_if_dir(opt.ICLABEL_ROOT);
        add_if_dir(opt.CLEANLINE_ROOT);
        if opt.SavePath
            savepath;
        end
    end

    % Checks
    report.EEGflow = check_fn('prep.load_set');
    report.EEGLAB = check_fn('pop_loadset');
    report.FASTER = check_fn('FASTER_rejchan');
    report.ICLabel = check_fn('iclabel');
    report.CleanLine = check_fn('cleanline');

    % Print summary
    fprintf('EEGflow Doctor Summary:\n');
    disp(report);

    function add_if_dir(pth)
        if isempty(pth), return; end
        if exist(pth, 'dir')
            addpath(genpath(char(pth)));
        end
    end

    function ok = check_fn(fnname)
        ok = ~isempty(which(fnname));
        if ~ok
            report.missing{end+1} = fnname; %#ok<AGROW>
        end
    end
end
