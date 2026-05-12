%% === ERP cluster stats tests ===
clear; clc;
rng(12);

fprintf('Running analysis_erp_cluster_stats_test...\n');

subjects = arrayfun(@(x) sprintf('sub_%02d', x), 1:10, 'UniformOutput', false);
conditions = {'cond_a', 'cond_b'};
nchan = 3;
ntime = 81;
ntrial = 18;
times = linspace(-200, 600, ntime);
effect_mask = times >= 250 & times <= 390;
chanlocs = struct('labels', {'Fz', 'Cz', 'Pz'});

Out = struct();
Out.meta = struct();
Out.meta.conditions = conditions;
Out.meta.chanlocs = chanlocs;
Out.meta.times = times;
Out.meta.fs = 100;
Out.meta.srate = 100;
Out.meta.toolbox_version = analysis.get_version();

trialN = zeros(numel(subjects), numel(conditions));
for i = 1:numel(subjects)
    sid = subjects{i};
    base = randn(nchan, ntime, ntrial) * 0.15;
    cond_a = base + randn(nchan, ntime, ntrial) * 0.05;
    cond_b = base + randn(nchan, ntime, ntrial) * 0.05;
    cond_b(:, effect_mask, :) = cond_b(:, effect_mask, :) + 1.25;

    Out.(sid).cond_a = cond_a;
    Out.(sid).cond_b = cond_b;
    trialN(i, :) = [size(cond_a, 3), size(cond_b, 3)];
end
Out.meta.trialN = table(subjects', trialN(:,1), trialN(:,2), ...
    'VariableNames', {'sub', 'cond_a', 'cond_b'});
Out.meta.summary = Out.meta.trialN;

ds = analysis.Dataset(Out);
state = analysis.init_state(ds);
state = analysis.define_group(state, struct('name', 'All', 'subjects', {ds.get_subjects()}));
state = analysis.select_conditions(state, struct('conditions', {conditions}));
state = analysis.define_roi(state, struct('name', 'Midline', 'labels', {{'Fz', 'Cz', 'Pz'}}));
state = analysis.erp_compute_erps(state, struct('method', 'mean'));
state = analysis.erp_compute_ga(state, struct());

state = analysis.erp_define_contrast(state, struct( ...
    'name', 'b_minus_a_ga', ...
    'pos_term', {{'All', 'cond_b'}}, ...
    'neg_term', {{'All', 'cond_a'}}));

state = analysis.erp_compute_stats(state, struct( ...
    'contrast', 'b_minus_a_ga', ...
    'roi', 'Midline', ...
    'mcc', 'cluster', ...
    'n_perm', 60, ...
    'seed', 11));

GAStats = state.Results.Contrasts.b_minus_a_ga.Stats;
assert(strcmpi(GAStats.mcc, 'cluster'), 'GA stats should record cluster correction.');
assert(isfield(GAStats, 'clusters'), 'GA stats should store cluster metadata.');
assert(isfield(GAStats, 'subjects_included'), 'GA stats should store included subjects.');
assert(numel(GAStats.subjects_included) == numel(subjects), 'All paired subjects should be included.');
assert(any(GAStats.h(1, effect_mask)), 'GA cluster stats should detect the synthetic effect window.');

state = analysis.erp_compute_subject_contrast(state, struct( ...
    'name', 'b_minus_a_subject', ...
    'pos_term', {{'All', 'cond_b'}}, ...
    'neg_term', {{'All', 'cond_a'}}));

state = analysis.erp_compute_subject_contrast_stats(state, struct( ...
    'contrast', 'b_minus_a_subject', ...
    'roi', 'Midline', ...
    'mcc', 'cluster', ...
    'n_perm', 60, ...
    'seed', 11));

SCStats = state.Results.SubjectContrasts.b_minus_a_subject.Stats;
assert(strcmpi(SCStats.mcc, 'cluster'), 'Subject contrast stats should record cluster correction.');
assert(isfield(SCStats, 'clusters'), 'Subject contrast stats should store cluster metadata.');
assert(isfield(SCStats, 'subjects_included'), 'Subject contrast stats should store included subjects.');
assert(numel(SCStats.subjects_included) == numel(subjects), 'All subject contrast subjects should be included.');
assert(any(SCStats.h(1, effect_mask)), 'Subject contrast cluster stats should detect the synthetic effect window.');

fprintf('analysis_erp_cluster_stats_test passed.\n');
