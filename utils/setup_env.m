function setup_env()
%SETUP Verify environment variables and add paths
    required_vars = {'EEGFLOW_ROOT', 'EEGLAB_ROOT', 'FASTER_ROOT'};

    for i = 1:numel(required_vars)
        varName = required_vars{i};
        pathVal = getenv(varName);

        if isempty(pathVal) || ~isfolder(pathVal)
            error('PrepCtx:Setup', 'Environment variable %s is missing or invalid.', varName);
        end

        addpath(genpath(pathVal));
    end

    % Avoid common MATLAB built-in shadowing from third-party toolboxes.
    % EEGdojo ships a script named "extract.m" that can break MATLAB graphics.
    local_fix_shadowed_extract();

    % Plot text often includes underscores (e.g., subject IDs). Use literal text by default.
    local_set_plot_text_interpreter_none();

    % Ensure the output folder exists (optional convention)
    outDir = fullfile(getenv('EEGFLOW_ROOT'), 'output');
    if ~isfolder(outDir), mkdir(outDir); end
end

function local_fix_shadowed_extract()
    % If a toolbox script shadows MATLAB's extract(), remove the offending folder.
    try
        w = which('extract');
        if isempty(w) || ~ischar(w)
            return;
        end

        % When shadowed, this is typically a .m script outside matlabroot.
        isMatlab = contains(w, matlabroot, 'IgnoreCase', true);
        if isMatlab
            return;
        end

        if endsWith(w, [filesep 'extract.m'], 'IgnoreCase', true)
            badDir = fileparts(w);
            if isfolder(badDir)
                warning('setup_env:PathSanitize', ...
                    'Removing folder shadowing MATLAB extract(): %s', badDir);
                rmpath(badDir);
            end
        end
    catch
        % best-effort only
    end
end

function local_set_plot_text_interpreter_none()
    try
        set(groot, 'defaultTextInterpreter', 'none');
        set(groot, 'defaultLegendInterpreter', 'none');
        set(groot, 'defaultAxesTickLabelInterpreter', 'none');
    catch
        % best-effort only
    end
end
