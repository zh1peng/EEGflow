# ERP Analysis Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve ERP analysis reliability by adding waveform cluster permutation correction, shared stats plumbing, and explicit subject inclusion reporting.

**Architecture:** Keep public ERP APIs compatible. Move repeated waveform statistics behavior into a focused private helper used by both `erp_compute_stats` and `erp_compute_subject_contrast_stats`; store corrected masks and cluster metadata under existing `Stats` structs.

**Tech Stack:** MATLAB R2025b, EEGLAB-compatible package layout, existing `analysis.Dataset` and state struct APIs.

---

### Task 1: Regression Tests For ERP Cluster Statistics

**Files:**
- Create: `test/analysis_erp_cluster_stats_test.m`

- [x] **Step 1: Write the failing test**

Create a synthetic ERP dataset with a stable time-localized condition effect. Exercise both public stats APIs:

```matlab
state = analysis.erp_compute_stats(state, struct( ...
    'contrast', 'b_minus_a_ga', ...
    'roi', 'Midline', ...
    'mcc', 'cluster', ...
    'n_perm', 60, ...
    'seed', 11));

state = analysis.erp_compute_subject_contrast_stats(state, struct( ...
    'contrast', 'b_minus_a_subject', ...
    'roi', 'Midline', ...
    'mcc', 'cluster', ...
    'n_perm', 60, ...
    'seed', 11));
```

Expected assertions:

```matlab
assert(strcmpi(state.Results.Contrasts.b_minus_a_ga.Stats.mcc, 'cluster'));
assert(isfield(state.Results.Contrasts.b_minus_a_ga.Stats, 'clusters'));
assert(any(state.Results.Contrasts.b_minus_a_ga.Stats.h(effect_mask)));
assert(isfield(state.Results.Contrasts.b_minus_a_ga.Stats, 'subjects_included'));
assert(strcmpi(state.Results.SubjectContrasts.b_minus_a_subject.Stats.mcc, 'cluster'));
assert(isfield(state.Results.SubjectContrasts.b_minus_a_subject.Stats, 'clusters'));
assert(any(state.Results.SubjectContrasts.b_minus_a_subject.Stats.h(effect_mask)));
```

- [x] **Step 2: Run test to verify it fails**

Run:

```powershell
matlab -batch "addpath(genpath(pwd)); run('test/analysis_erp_cluster_stats_test.m')"
```

Expected: FAIL with `mcc must be "none" or "fdr"` or missing cluster fields.

### Task 2: Shared ERP Waveform Stats Helper

**Files:**
- Create: `+analysis/private/erp_waveform_stats.m`
- Modify: `+analysis/erp_compute_stats.m`
- Modify: `+analysis/erp_compute_subject_contrast_stats.m`

- [x] **Step 1: Implement minimal helper**

Create a private helper that accepts row x time x subject arrays and supports:

```matlab
S = erp_waveform_stats(X1, X2, design, times, args);
```

Supported `design` values:

```matlab
'onesample'
'two-sample'
```

Supported correction values:

```matlab
'none'
'fdr'
'cluster'
```

For `cluster`, use sign-flip permutations for one-sample data and label permutations for two-sample data. Store `S.p`, `S.p_corrected`, `S.t`, `S.h`, `S.sig_segments`, `S.clusters`, `S.alpha`, `S.mcc`, `S.n_perm`, `S.tail`, and `S.time_window`.

- [x] **Step 2: Wire public stats functions to helper**

`erp_compute_stats` should keep its current public signature and paired-design inference. For paired designs, pass subject differences into the helper as `onesample`; for between-group designs, pass positive and negative ERP stacks as `two-sample`.

`erp_compute_subject_contrast_stats` should pass subject contrast waves into the helper as `onesample`.

- [x] **Step 3: Preserve backwards compatibility**

Keep existing `Stats.sig_clusters` as an alias for `Stats.sig_segments`. Keep `mcc='none'` and `mcc='fdr'` behavior compatible.

### Task 3: Subject Inclusion Reporting

**Files:**
- Modify: `+analysis/erp_compute_stats.m`
- Modify: `+analysis/erp_compute_subject_contrast_stats.m`

- [x] **Step 1: Store included and excluded subjects**

For `erp_compute_stats`, store:

```matlab
Stats.subjects_positive
Stats.subjects_negative
Stats.subjects_included
Stats.subjects_excluded
Stats.design
Stats.is_paired
```

For `erp_compute_subject_contrast_stats`, store:

```matlab
Stats.subjects_included
Stats.n_subjects
Stats.design = 'onesample'
```

### Task 4: Documentation

**Files:**
- Modify: `docs/erp.md`
- Modify: `changelog.md`

- [x] **Step 1: Document cluster correction**

Update ERP stats docs so `mcc` lists `'none'`, `'fdr'`, and `'cluster'`, and explain that cluster correction is time-contiguous waveform cluster-mass permutation.

- [x] **Step 2: Document inclusion report fields**

Document that stats results store included/excluded subject fields for reproducibility.

### Task 5: Verification

**Files:**
- Test: `test/analysis_erp_cluster_stats_test.m`
- Test: `test/analysis_erp_subject_contrast_test.m`

- [x] **Step 1: Run focused tests**

Run:

```powershell
matlab -batch "addpath(genpath(pwd)); run('test/analysis_erp_cluster_stats_test.m'); run('test/analysis_erp_subject_contrast_test.m')"
```

Expected: both scripts finish without assertion failures.

- [x] **Step 2: Review changed files**

Run:

```powershell
git diff -- +analysis docs test changelog.md
```

Expected: only ERP analysis, ERP docs, tests, and changelog files are changed.
