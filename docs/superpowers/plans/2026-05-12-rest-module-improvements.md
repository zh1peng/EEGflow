# Rest Module Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the resting-state module easier to extend and more complete by normalizing parameters, improving power/peak-frequency behavior, and exporting core rest features beyond graph metrics.

**Architecture:** Keep `rest.compute_all_features` as the backward-compatible public orchestrator, but move reusable behavior into smaller `+rest` functions. Add focused MATLAB tests that run without FieldTrip for the pure feature/export paths, so future rest analysis changes have fast regression coverage.

**Tech Stack:** MATLAB R2025b, EEGLAB/FieldTrip-compatible structs, EEGflow state + pipeline conventions.

---

### File Structure

- Create: `+rest/normalize_params.m` for compatibility aliases and derived defaults.
- Create: `+rest/compute_bandpower.m` for absolute and relative sensor band power summaries.
- Modify: `+rest/compute_power.m` to honor `PowerFreqRange`, `PowerFoi`, and existing taper/pad settings.
- Modify: `+rest/compute_peakfrequency.m` to support a configurable peak band while preserving `alpha` defaults.
- Modify: `+rest/compute_all_features.m` to call `normalize_params`, add sensor band-power output, and keep old fields.
- Modify: `+rest/features2csv.m` and `+rest/features2csv_parallel.m` to export aperiodic and sensor band-power summaries.
- Create: `test/rest_module_improvements_test.m` with pure MATLAB regression tests.

### Task 1: Parameter Normalization

**Files:**
- Create: `+rest/normalize_params.m`
- Test: `test/rest_module_improvements_test.m`

- [ ] **Step 1: Write failing tests**

Create tests that call `rest.normalize_params` with legacy fields and assert normalized fields exist:

```matlab
function test_normalize_params_aliases()
params = struct();
params.nTrial_treshold = 12;
params.FreqRes = 0.25;
params.FreqBand = struct('theta', [4 8], 'alpha', [8 12]);
R = rest.normalize_params(params);
assert(R.MinTrials == 12);
assert(R.nTrial_treshold == 12);
assert(R.PowerFreqStep == 0.25);
assert(isfield(R, 'PeakBand'));
assert(strcmp(R.PeakBand, 'alpha'));
assert(isequal(R.PowerFreqRange, [1 100]));
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `matlab -batch "addpath(genpath(pwd)); test.rest_module_improvements_test"`

Expected: FAIL because `rest.normalize_params` does not exist.

- [ ] **Step 3: Implement `normalize_params`**

Add a function that maps `MinTrials` and legacy `nTrial_treshold`, maps `PowerFreqStep` and legacy `FreqRes`, supplies `PowerFreqRange`, and supplies `PeakBand='alpha'`.

- [ ] **Step 4: Run test to verify it passes**

Run: `matlab -batch "addpath(genpath(pwd)); test.rest_module_improvements_test"`

Expected: PASS for parameter normalization tests.

### Task 2: Power and Peak-Frequency Improvements

**Files:**
- Modify: `+rest/compute_power.m`
- Modify: `+rest/compute_peakfrequency.m`
- Create: `+rest/compute_bandpower.m`
- Test: `test/rest_module_improvements_test.m`

- [ ] **Step 1: Write failing tests**

Add tests with synthetic FieldTrip-like power structs:

```matlab
function test_peakfrequency_uses_configurable_band()
power = local_power_struct(1:0.5:30, [1:0.5:30]);
power.powspctrm = exp(-0.5 .* ((power.freq - 6) ./ 0.8).^2);
params = rest.normalize_params(struct('FreqBand', struct('theta', [4 8]), 'PeakBand', 'theta'));
pf = rest.compute_peakfrequency(power, params);
assert(abs(pf.localmax - 6) <= 0.5);
assert(strcmp(pf.band, 'theta'));
assert(pf.peak_found);
end

function test_bandpower_exports_absolute_and_relative_power()
freq = 1:1:20;
power = local_power_struct(freq, ones(2, numel(freq)));
params = rest.normalize_params(struct('FreqBand', struct('theta', [4 8], 'alpha', [8 12])));
bp = rest.compute_bandpower(power, params);
assert(isfield(bp, 'theta'));
assert(isfield(bp.theta, 'absolute_mean'));
assert(isfield(bp.theta, 'relative_mean'));
assert(bp.theta.absolute_mean > 0);
assert(bp.theta.relative_mean > 0);
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `matlab -batch "addpath(genpath(pwd)); test.rest_module_improvements_test"`

Expected: FAIL because `compute_bandpower` does not exist and peak-frequency lacks configurable metadata.

- [ ] **Step 3: Implement minimal code**

Update `compute_peakfrequency` to use `params.PeakBand`, add `band`, `range_hz`, `peak_found`, and robust NaN behavior. Add `compute_bandpower` using trapezoidal integration across each configured frequency band.

- [ ] **Step 4: Run tests**

Run: `matlab -batch "addpath(genpath(pwd)); test.rest_module_improvements_test"`

Expected: PASS for pure power/peak tests.

### Task 3: Orchestrator and Export Coverage

**Files:**
- Modify: `+rest/compute_all_features.m`
- Modify: `+rest/features2csv.m`
- Modify: `+rest/features2csv_parallel.m`
- Test: `test/rest_module_improvements_test.m`

- [ ] **Step 1: Write failing export test**

Create a temporary `res` MAT file containing `bandpower` and `aperiodic`, export CSV, and assert the new columns exist:

```matlab
function test_features2csv_exports_bandpower_and_aperiodic()
tmpDir = tempname;
mkdir(tmpDir);
res = struct();
res.subid = "sub-test";
res.nTrial = 20;
res.params = struct('FreqBand', struct('theta', [4 8], 'alpha', [8 12]));
res.bandpower.theta.absolute_mean = 2;
res.bandpower.theta.relative_mean = 0.2;
res.bandpower.alpha.absolute_mean = 3;
res.bandpower.alpha.relative_mean = 0.3;
res.aperiodic.exponent_mean = 1.1;
res.aperiodic.offset_mean = -0.5;
res.aperiodic.r2_mean = 0.9;
res.peakfrequency.localmax = 10;
res.peakfrequency.cog = 9.8;
matFile = fullfile(tmpDir, 'sub-test_rest_features.mat');
save(matFile, 'res');
csvFile = fullfile(tmpDir, 'features.csv');
rest.features2csv({matFile}, csvFile);
T = readtable(csvFile);
assert(ismember('theta_power_abs_mean', T.Properties.VariableNames));
assert(ismember('alpha_power_rel_mean', T.Properties.VariableNames));
assert(ismember('aperiodic_exponent_mean', T.Properties.VariableNames));
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `matlab -batch "addpath(genpath(pwd)); test.rest_module_improvements_test"`

Expected: FAIL because export does not include the new feature columns.

- [ ] **Step 3: Implement orchestrator/export changes**

Call `rest.normalize_params` in `compute_all_features`, use `R.MinTrials`, add `res.bandpower = rest.compute_bandpower(res.power, R)`, and export bandpower/aperiodic columns in both serial and parallel exporters.

- [ ] **Step 4: Run tests**

Run: `matlab -batch "addpath(genpath(pwd)); test.rest_module_improvements_test"`

Expected: PASS.

### Task 4: Verification

**Files:**
- Test: `test/rest_module_improvements_test.m`
- Existing optional integration: `test/rest_end_to_end.m`

- [ ] **Step 1: Run pure regression tests**

Run: `matlab -batch "addpath(genpath(pwd)); test.rest_module_improvements_test"`

Expected: all test functions print `[OK]`.

- [ ] **Step 2: Run syntax smoke check**

Run: `matlab -batch "addpath(genpath(pwd)); which rest.compute_all_features; which rest.compute_power; which rest.features2csv"`

Expected: MATLAB resolves all functions under `+rest`.

- [ ] **Step 3: Report verification**

Report exact commands run and whether they passed. If `git` remains blocked by safe.directory, report that staging/committing was not attempted.
