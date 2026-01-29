function setup()
%SETUP Verify environment variables and add paths
    required_vars = {'EEGDOJO_ROOT', 'EEGLAB_ROOT', 'FASTER_ROOT'};

    for i = 1:numel(required_vars)
        varName = required_vars{i};
        pathVal = getenv(varName);

        if isempty(pathVal) || ~isfolder(pathVal)
            error('PrepCtx:Setup', 'Environment variable %s is missing or invalid.', varName);
        end

        addpath(genpath(pathVal));
    end

    % Ensure the output folder exists (optional convention)
    outDir = fullfile(getenv('EEGDOJO_ROOT'), 'output');
    if ~isfolder(outDir), mkdir(outDir); end
end
