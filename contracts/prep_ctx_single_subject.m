%% prep_ctx_single_subject.m
% Demo script for prep_ctx Pipeline (context + registry + step specs)

%% 0. Setup
% setenv('EEGLAB_ROOT', 'Z:\matlab_toolbox\eeglab2023.1');
% setenv('FASTER_ROOT', 'Z:\matlab_toolbox\FASTER');
% setenv('EEGDOJO_ROOT', 'Z:\matlab_toolbox\EEGdojo');
clear; close all; clc;
% setup();
eegdojoRoot = getenv('EEGDOJO_ROOT');
thisDir = fullfile(eegdojoRoot, 'tutorials', 'prep_ctx');
outDir = fullfile(thisDir, 'output');
if ~isfolder(outDir), mkdir(outDir); end

%% 1. Load template params and step spec
Params = load_params(fullfile(eegdojoRoot, 'params', 'prep_ctx', 'prep_ctx_params_template.json'));
p = Params;
% Localize paths for this tutorial
dataDir = fullfile(eegdojoRoot, 'tutorials', 'prep', 'data');
p.Input.filepath = dataDir;
% Setup log paths/files and output filename
p.Output.filepath = outDir;
p = setup_params(p);
%% 2. Build pipeline (context + registry + steps)
pipe = prep_ctx.build_pipeline(p);

%% 4. Run (or validate)
do_validate = false;
if isfield(p, 'Options') && isfield(p.Options, 'validate_only')
    do_validate = logical(p.Options.validate_only);
end

if do_validate
    [context, report] = pipe.validate('stop_on_error', true);
else
    [context, report] = pipe.run();
end

fprintf('--- prep_ctx demo finished. ok=%d, steps=%d ---\n', report.ok, report.n_steps);
