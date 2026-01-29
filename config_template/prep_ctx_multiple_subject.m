%% prep_ctx_multiple_subject.m
% Batch preprocessing for multiple participants using prep_ctx pipeline

%% 0. Setup
% setenv('EEGLAB_ROOT', 'Z:\matlab_toolbox\eeglab2023.1');
% setenv('FASTER_ROOT', 'Z:\matlab_toolbox\FASTER');
% setenv('EEGDOJO_ROOT', 'Z:\matlab_toolbox\EEGdojo');

clear; close all; clc;
% setup();
eegdojoRoot = getenv('EEGDOJO_ROOT');
thisDir = fullfile(eegdojoRoot, 'tutorials', 'prep_ctx');
dataDir = fullfile(eegdojoRoot, 'tutorials', 'prep', 'data');
outDir  = fullfile(thisDir, 'output');
if ~isfolder(outDir), mkdir(outDir); end

% find all subjects
[paths, names] = filesearch_regexp(dataDir, 'sub-.*_eeg\.set$');
if isempty(names)
    error('No .set files found in %s', dataDir);
end

% load params template once
Params = load_params(fullfile(eegdojoRoot, 'params', 'prep_ctx', 'prep_ctx_params_template.json'));
for i = 1:numel(names)
    fprintf('--- Processing %s (%d/%d) ---\n', names{i}, i, numel(names));

    p = Params;
    p.Input.filepath = paths{i};
    p.Input.filename = names{i};
    p.Output.filepath = outDir;
    p = setup_params(p);

    try
        pipe = prep_ctx.build_pipeline(p);
        [context, report] = pipe.run('stop_on_error', true);

        fprintf('--- Finished %s | ok=%d steps=%d ---\n', names{i}, report.ok, report.n_steps);
    catch ME
        fprintf(2, 'ERROR processing %s: %s\n', names{i}, ME.message);
    end
end

fprintf('=== All subjects finished ===\n');
