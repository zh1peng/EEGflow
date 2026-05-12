# TF Module Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make EEGflow TF downstream analyses consume a single canonical TF/contrast representation so band statistics, feature extraction, plotting, and future stats behave consistently.

**Architecture:** Keep `analysis.tf_transform` as the canonical TF engine and add small private helpers for TF axis lookup and contrast-array extraction. Refactor `tf_band_stats` to compute windowed statistics from already-built contrast maps instead of reconstructing terms from raw conditions.

**Tech Stack:** MATLAB R2025b, EEGLAB-compatible structs, package functions under `+analysis`, script-style MATLAB regression tests under `test/`.

---

### Task 1: Add Regression Test For Contrast-Based Band Stats

**Files:**
- Create: `test/analysis_tf_contrast_band_stats_test.m`
- Modify: none

- [ ] **Step 1: Write the failing test**

Create a synthetic TF dataset with two metrics, `power` and `induced_power`. Build a diff-in-diff contrast with `metric='induced_power'`, then run `analysis.tf_band_stats`. The expected statistic must be computed from the contrast maps, not from the raw `power` condition fields.

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
matlab -batch "addpath(genpath(pwd)); run('test/analysis_tf_contrast_band_stats_test.m')"
```

Expected: FAIL before implementation because `tf_band_stats` hard-codes `power` and does not consume diff-in-diff contrast maps.

### Task 2: Add TF Axis Helper

**Files:**
- Create: `+analysis/private/state_get_tf_axes.m`
- Modify: `+analysis/tf_compute_ga.m`
- Modify: `+analysis/tf_contrast_maps.m`
- Modify: `+analysis/tf_contrast_maps_between.m`
- Modify: `+analysis/tf_extract_features.m`
- Modify: `+analysis/tf_plot.m`

- [ ] **Step 1: Implement helper**

Add `state_get_tf_axes(state, subjects, condition, contrast)` that resolves axes in this priority order:

1. `contrast.freqs` and `contrast.times`
2. `state.Dataset.data.meta.freqs` and `state.Dataset.data.meta.times`
3. `state.Results.TF.(subject).(condition).freqs/times`

- [ ] **Step 2: Replace duplicated local resolvers**

Replace duplicated `resolve_tf_axes` calls with `state_get_tf_axes`. Remove local duplicate helper functions from files touched in this task.

- [ ] **Step 3: Run focused test**

Run:

```powershell
matlab -batch "addpath(genpath(pwd)); run('test/analysis_tf_contrast_band_stats_test.m')"
```

Expected: still FAIL until `tf_band_stats` is refactored, but no undefined helper errors.

### Task 3: Add Contrast Array Helper And Refactor Band Stats

**Files:**
- Create: `+analysis/private/state_get_tf_contrast_arrays.m`
- Modify: `+analysis/tf_band_stats.m`

- [ ] **Step 1: Implement contrast array helper**

Add `state_get_tf_contrast_arrays(state, contrast)` returning:

- `design`: `'onesample'`, `'paired'`, or `'two-sample'`
- `X1`: `[chan x freq x time x subject]`
- `X2`: empty for onesample, otherwise second sample array
- `metric`: contrast metric or `'power'`
- `subjects1`, `subjects2`

For `.maps`, return one-sample maps versus zero. For `.pos_maps/.neg_maps`, return paired arrays only when `contrast.design` is `'paired'`; otherwise return two-sample arrays.

- [ ] **Step 2: Refactor `tf_band_stats`**

Compute `vp` and `vn` from the helper arrays. For onesample contrasts, test the reduced contrast values against zero with `ttest`. For paired contrasts, use `ttest(vp, vn)`. For between/diff-in-diff contrasts, use `ttest2(vp, vn)`. Store `metric`, `design`, `n_pos`, `n_neg`, `pos_mean`, and `neg_mean`.

- [ ] **Step 3: Run regression test**

Run:

```powershell
matlab -batch "addpath(genpath(pwd)); run('test/analysis_tf_contrast_band_stats_test.m')"
```

Expected: PASS.

### Task 4: Update TF Documentation

**Files:**
- Modify: `docs/tf.md`

- [ ] **Step 1: Document canonical contrast behavior**

Add a note that `tf_band_stats` consumes stored subject-level contrast maps and respects `contrast.metric`.

- [ ] **Step 2: Run smoke test**

Run:

```powershell
matlab -batch "addpath(genpath(pwd)); run('test/analysis_tf_contrast_band_stats_test.m')"
```

Expected: PASS.

### Task 5: Final Verification

**Files:**
- Test: `test/analysis_tf_contrast_band_stats_test.m`
- Optional Test: `test/analysis_erp_subject_contrast_test.m`

- [ ] **Step 1: Run focused TF regression**

Run:

```powershell
matlab -batch "addpath(genpath(pwd)); run('test/analysis_tf_contrast_band_stats_test.m')"
```

Expected: PASS.

- [ ] **Step 2: Run existing lightweight analysis regression**

Run:

```powershell
matlab -batch "addpath(genpath(pwd)); run('test/analysis_erp_subject_contrast_test.m')"
```

Expected: PASS or report dependency/data blocker exactly.

---

## Self-Review

- Spec coverage: covers unified TF axis resolution, contrast-map-driven band stats, metric preservation, and focused verification.
- Placeholder scan: no TBD/TODO placeholders.
- Type consistency: helper names and array shapes are consistent across tasks.
