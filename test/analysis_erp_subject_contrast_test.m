%% === Subject-level ERP contrast + Dataset merge tests ===
clear; clc;
rng(7);

fprintf('Running analysis_erp_subject_contrast_test...\n');

%% Build synthetic Out
subjects = {'sub_01', 'sub_02', 'sub_03'};
conditions = {'cond_a', 'cond_b', 'cond_c'};
nchan = 3;
ntime = 41;
times = linspace(-100, 300, ntime);
chanlocs = struct('labels', {'Fz', 'Cz', 'Pz'});

Out = struct();
Out.meta = struct();
Out.meta.conditions = conditions;
Out.meta.chanlocs = chanlocs;
Out.meta.times = times;
Out.meta.fs = 250;
Out.meta.srate = 250;
Out.meta.toolbox_version = analysis.get_version();

trialN = zeros(numel(subjects), numel(conditions));
for i = 1:numel(subjects)
    sid = subjects{i};
    A = randn(nchan, ntime, 20) * 0.8;
    B = randn(nchan, ntime, 18) * 0.8 + 1.0;  % positive shift vs A
    C = randn(nchan, ntime, 15) * 0.8 - 0.5;
    Out.(sid).cond_a = A;
    Out.(sid).cond_b = B;
    Out.(sid).cond_c = C;
    trialN(i, :) = [size(A,3), size(B,3), size(C,3)];
end
Out.meta.trialN = table(subjects', trialN(:,1), trialN(:,2), trialN(:,3), ...
    'VariableNames', {'sub', 'cond_a', 'cond_b', 'cond_c'});
Out.meta.summary = Out.meta.trialN;

ds = analysis.Dataset(Out);

%% Dataset.merge strict checks
ok = false;
try
    ds.merge('cond_a', {'cond_b', 'cond_c'}); %#ok<NASGU>
catch ME
    ok = contains(lower(ME.message), 'already exists');
end
assert(ok, 'Expected merge to fail on existing condition name.');

ok = false;
try
    ds.merge('cond_bc_missing', {'cond_b', 'cond_x'}); %#ok<NASGU>
catch ME
    ok = contains(lower(ME.message), 'missing');
end
assert(ok, 'Expected merge to fail on missing source condition.');

Out_bad = Out;
Out_bad.sub_02.cond_c = randn(nchan, ntime+1, 10);
ds_bad = analysis.Dataset(Out_bad);
ok = false;
try
    ds_bad.merge('bad_merge', {'cond_b', 'cond_c'}); %#ok<NASGU>
catch ME
    ok = contains(lower(ME.message), 'size mismatch');
end
assert(ok, 'Expected merge to fail on channel/time mismatch.');

%% Dataset.merge success path
ds2 = ds.merge('cond_bc', {'cond_b', 'cond_c'});
assert(ismember('cond_bc', ds2.conditions), 'Merged condition should be appended to ds.conditions.');
assert(isfield(ds2.data.meta, 'derived_conditions') && ~isempty(ds2.data.meta.derived_conditions), ...
    'derived_conditions should be recorded in metadata.');
assert(ismember('cond_bc', ds2.data.meta.trialN.Properties.VariableNames), ...
    'trialN should include merged condition column.');
assert(ismember('cond_bc', ds2.data.meta.summary.Properties.VariableNames), ...
    'summary should include merged condition column.');

for i = 1:numel(subjects)
    sid = subjects{i};
    expected_trials = size(ds.data.(sid).cond_b, 3) + size(ds.data.(sid).cond_c, 3);
    assert(size(ds2.data.(sid).cond_bc, 3) == expected_trials, 'Merged trial count mismatch.');
    assert(isequal(ds2.data.(sid).cond_b, ds.data.(sid).cond_b), 'Source condition cond_b should remain unchanged.');
    assert(isequal(ds2.data.(sid).cond_c, ds.data.(sid).cond_c), 'Source condition cond_c should remain unchanged.');
end
assert(~isempty(ds2.get_data('sub_01', 'COND_BC')), 'get_data should resolve condition keys case-insensitively.');

%% Subject contrast workflow
state = analysis.init_state(ds2);
state = analysis.define_group(state, struct('name', 'All', 'subjects', {ds2.get_subjects()}));
state = analysis.select_conditions(state, struct('conditions', {{'cond_a', 'cond_b', 'cond_c', 'cond_bc'}}));
state = analysis.define_roi(state, struct('name', 'Front', 'labels', {{'Fz', 'Cz'}}));
state = analysis.define_time_window(state, struct('name', 'Early', 'range', [0 150]));

state = analysis.erp_compute_erps(state, struct('method', 'mean'));
state = analysis.erp_compute_subject_contrast(state, struct( ...
    'name', 'b_minus_a', ...
    'pos_term', {{'All', 'cond_b'}}, ...
    'neg_term', {{'All', 'cond_a'}}));

assert(isfield(state.Results.SubjectContrasts, 'b_minus_a'), 'Subject contrast result missing.');
C = state.Results.SubjectContrasts.b_minus_a;
assert(size(C.erps, 3) == numel(subjects), 'Subject contrast should keep all subjects.');
assert(C.n == numel(subjects), 'Subject contrast N mismatch.');

state = analysis.erp_compute_subject_contrast_stats(state, struct( ...
    'contrast', 'b_minus_a', ...
    'roi', 'Front', ...
    'mcc', 'none'));
assert(isfield(state.Results.SubjectContrasts.b_minus_a, 'Stats'), 'Subject contrast stats missing.');
assert(size(state.Results.SubjectContrasts.b_minus_a.Stats.p, 1) == 1, ...
    'ROI stats should produce one-row output.');

analysis.erp_plot_subject_contrast(state, struct( ...
    'contrast', 'b_minus_a', ...
    'target', 'Front', ...
    'show_sig', true), struct());

[state, T] = analysis.erp_extract_subject_contrast_feature(state, struct( ...
    'contrast', 'b_minus_a', ...
    'roi', 'Front', ...
    'time_window', 'Early', ...
    'feature_func', 'mean'));
assert(height(T) == numel(subjects), 'Feature table row count should equal subject count.');
assert(ismember('Contrast', T.Properties.VariableNames), 'Feature table should contain Contrast column.');

%% Strict missing-condition behavior in subject contrast
ok = false;
try
    analysis.erp_compute_subject_contrast(state, struct( ...
        'name', 'bad_missing', ...
        'pos_term', {{'All', 'cond_a'}}, ...
        'neg_term', {{'All', 'cond_x'}}));
catch ME
    ok = contains(lower(ME.message), 'missing');
end
assert(ok, 'Expected strict error for missing subject-condition in subject contrast.');

fprintf('analysis_erp_subject_contrast_test passed.\n');
