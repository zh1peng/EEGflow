# EEGflow Time-Frequency (TF/TFR) Analysis Guide (`+analysis`)

This document explains how to run time-frequency analysis with EEGflow's `+analysis` module.
It focuses on:

1. Computing time-frequency representations (TFRs) for epoched EEG
2. Caching and reusing TFR results
3. Group-level summaries, contrasts, statistics, and plots
4. Extracting band x time-window features as tables for downstream stats

This guide is written against the current code in `+analysis/`.

---

## 0) Where TF Analysis Fits in EEGflow

Typical workflow:

1. Preprocess cleaned task EEG using `+prep` and save cleaned `.set`
2. Build an epoched dataset using `analysis.extract_epoch`
3. Compute TFRs:
   - recommended: `analysis.tf_transform` (returns an `Out_tfd` struct)
   - optional: `analysis.tf_compute` (stores TF in `state.Results.TF`)
4. Compute group-level GA TFRs (`analysis.tf_compute_ga`)
5. Define contrasts (within-group or between-group)
6. Run stats:
   - TF-plane cluster permutation (`analysis.tf_stats_plane`)
   - band/time window t-tests (`analysis.tf_band_stats`)
7. Plot and export features

---

## 1) Dependencies and Setup

### Required

- **EEGLAB**
  - `newtimef` is required by both `analysis.tf_transform` (when `method='eeglab'`) and `analysis.tf_compute`.

### Optional

- **Statistics and Machine Learning Toolbox**
  - required for `analysis.tf_stats_plane`, `analysis.tf_band_stats`, `analysis.tf_feature_stats`
- **Parallel Computing Toolbox**
  - optional for `analysis.tf_transform(..., 'parallel', true)`

### Recommended setup

```matlab
setenv('EEGFLOW_ROOT', 'Z:\matlab_toolbox\EEGflow');
setenv('EEGLAB_ROOT',  'Z:\matlab_toolbox\eeglab2023.1');
setenv('FASTER_ROOT',  'Z:\matlab_toolbox\FASTER');

addpath(genpath(getenv('EEGFLOW_ROOT')));
setup_env();
```

---

## 2) Quickstart: End-to-End TF Example (with Cache)

This example mirrors `test/analysis_tf_test.m`.

### 2.1 Build an epoched dataset

```matlab
dataset_path = fullfile(getenv('EEGFLOW_ROOT'), 'test', 'data', 'prep'); % change to your data folder

epoch_window = [-200 1000];
baseline = [-200 0];

Out = analysis.extract_epoch( ...
  'study_path',    dataset_path, ...
  'searchstring',  '^sub-.*_eeg_prep.set$', ...
  'subject_parser','(?<sub>sub-[^_]+)', ...
  'epoch_window',  epoch_window, ...
  'baseline',      baseline, ...
  'aliases',       {'10','win_cue'; '20','loss_cue'; '30','neut_cue'}, ...
  'markers',       {'10','20','30'} );

ds = analysis.Dataset(Out);
```

### 2.2 Compute TFR with `analysis.tf_transform`

`analysis.tf_transform` returns a TF container `Out_tfd` with canonical layout `cftt`:

- per-condition power: `[chan x freq x time]`
- per-condition ITC: `[chan x freq x time]`

Basic run:

```matlab
eeglab_params = {'freqs',[1 30], 'cycles',[2 0.5], 'timesout',400, 'padratio',2};
Out_tfd = analysis.tf_transform(ds, ...
  'method','eeglab', ...
  'params', eeglab_params, ...
  'baseline_range', baseline, ...
  'norm_type','decibel', ...
  'keep_trials','none', ...
  'parallel', false);
```

### 2.3 Cache and reload

```matlab
cache_dir = fullfile(getenv('EEGFLOW_ROOT'), 'test', 'out', 'tf_cache_demo');
if ~isfolder(cache_dir), mkdir(cache_dir); end

analysis.tf_cache_save(Out_tfd, struct('path', cache_dir, 'basename', 'tf_cache', 'overwrite', true));
Out_tfd = analysis.tf_cache_load(fullfile(cache_dir, 'tf_cache.mat'));
```

Optional compatibility check (useful when you change params):

```matlab
ok = analysis.tf_cache_is_compatible(Out_tfd, struct( ...
  'epoch_window', epoch_window, ...
  'freq_range', [1 30], ...
  'expected_params', eeglab_params));
assert(ok);
```

### 2.4 Create a TF dataset + state

For most downstream TF ops, it is convenient to create a Dataset over the TF container:

```matlab
ds_tfd = analysis.Dataset(Out_tfd);
state = analysis.init_state(ds_tfd);
```

### 2.5 Define groups/conditions/ROI and compute GA TFR

```matlab
conditions = {'win_cue','loss_cue','neut_cue'};
roi_labels = {'P5','P6','POz','PO3','PO4','PO5','PO6','PO7','PO8','Oz','O1','O2'};

state = analysis.define_group(state, struct('name','AllSubjects','subjects',{ds_tfd.get_subjects()}));
state = analysis.select_conditions(state, struct('conditions',{conditions}));
state = analysis.define_roi(state, struct('name','Pz_ROI','labels',{roi_labels}));

state = analysis.tf_compute_ga(state, struct('metric','power'));
```

### 2.6 Plot a TFR and a contrast

```matlab
analysis.tf_plot(state, struct('target','Pz_ROI','group','AllSubjects','condition','win_cue', 'freq_range',[1 30]), struct());
```

Build a within-group contrast from subject-level maps:

```matlab
state = analysis.tf_contrast_maps(state, struct( ...
  'name','win_vs_neut', ...
  'pos_term', {{'AllSubjects','win_cue'}}, ...
  'neg_term', {{'AllSubjects','neut_cue'}}, ...
  'metric','power', ...
  'require_complete', true));

analysis.tf_plot_contrast(state, struct('contrast','win_vs_neut','roi','Pz_ROI','freq_range',[3 30]), struct());
```

### 2.7 Stats and features

TF-plane cluster permutation (one-sample on contrast maps):

```matlab
state = analysis.tf_stats_plane(state, struct( ...
  'name','win_vs_neut_tf', ...
  'contrast','win_vs_neut', ...
  'roi','Pz_ROI', ...
  'design','onesample', ...
  'method','cluster', ...
  'n_perm',200, ...
  'alpha',0.05));
```

Band x time-window feature extraction:

```matlab
state = analysis.tf_define_band(state, struct('name','Alpha','range',[8 12]));
state = analysis.define_time_window(state, struct('name','P300','range',[300 600]));

[state, T] = analysis.tf_extract_features(state, struct( ...
  'roi','Pz_ROI', ...
  'band','Alpha', ...
  'window','P300', ...
  'metric','power', ...
  'per_subject', true, ...
  'metrics', {{'mean','peak','auc'}}));
```

---

## 3) TF Data Structures

### 3.1 `Out_tfd` from `analysis.tf_transform`

For each subject and condition:

- `Out_tfd.sub_<ID>.<cond>.power` : `[chan x freq x time]`
- `Out_tfd.sub_<ID>.<cond>.itc` : `[chan x freq x time]`
- optional fields depending on `keep_trials`:
  - `power_trials`, `phase`, `tf_complex`
- `Out_tfd.meta.freqs` : `[1 x F]` Hz
- `Out_tfd.meta.times` : `[1 x T]` ms

### 3.2 `state.Results.GA_TFD`

After `analysis.tf_compute_ga`:

- `state.Results.GA_TFD.(group).(cond).tfd`: `[chan x freq x time]` mean across subjects
- `state.Results.GA_TFD.(group).(cond).freqs`, `.times`

### 3.3 Contrasts

There are two common contrast representations:

- GA-level contrasts (quick difference of group means):
  - `analysis.tf_define_contrast` produces `state.Results.Contrasts.(name).tfd`
- subject-level maps (preferred for stats):
  - `analysis.tf_contrast_maps`: within-group maps `[chan x f x t x subj]` stored as `.maps`
  - `analysis.tf_contrast_maps_between`: between-group maps stored as `.pos_maps` and `.neg_maps`

`analysis.tf_stats_plane` expects contrasts with either `.maps` or `.pos_maps/.neg_maps`.

---

## 4) Function Reference (TF)

### 4.1 `analysis.tf_transform` (recommended)

High-level TFR runner on an `analysis.Dataset` (epoched time-domain data).

Key args:

- `method`: `'eeglab'` (default) or function handle
- `params`: EEGLAB `newtimef` name/value cell (for `method='eeglab'`)
- `baseline_range` (ms), `norm_type` (`'decibel'|'subtraction'|'z-score'|'percentage'`)
- `time_window` (ms) crop before TFR (optional)
- `keep_trials`: `'none'|'power'|'phase'|'complex'|'all'`
- `parallel`: boolean

### 4.2 Cache utilities

- `analysis.tf_cache_save(Out_tfd, struct('path',..., 'basename',..., 'overwrite',...))`
- `analysis.tf_cache_load(pathOrStruct)`
- `analysis.tf_cache_is_compatible(Out_tfd, struct('epoch_window',..., 'freq_range',..., 'expected_params',...))`

### 4.3 State-based TF compute (optional)

- `analysis.tf_compute(state, args)`
  - computes per-subject TFRs using `newtimef` and stores into `state.Results.TF`
  - useful for quick checks; can be slower than `tf_transform`

### 4.4 GA, bands, features

- `analysis.tf_compute_ga(state, struct('metric','power'))`
- `analysis.tf_define_band(state, struct('name','Alpha','range',[8 12]))`
- `analysis.tf_extract_features(state, struct(...))`
- `analysis.tf_feature_stats(state, struct(...))`

### 4.5 Contrasts and stats

- `analysis.tf_contrast_maps` (within-group; paired by subject)
- `analysis.tf_contrast_maps_between` (between-group; supports diff-in-diff)
- `analysis.tf_stats_plane` (cluster-permutation style TF-plane stats)
- `analysis.tf_band_stats` (ROI x band x time-window summary t-tests)

### 4.6 Plotting

- `analysis.tf_plot` (GA TFR images)
- `analysis.tf_plot_contrast` (contrast TFR images, optional mask overlay)
- `analysis.tf_plot_topo` (topography averaged in a band x window)
- `analysis.tf_plot_band_timecourse` (band-averaged timecourse)

---

## 5) Tutorial: Practical Notes and Design Choices

### 5.1 Low frequencies vs epoch length

Wavelet cycles and epoch length limit the lowest feasible frequency. If you see:

- missing time coverage
- errors like "not enough data points"

then:

- raise the minimum frequency (e.g., `freqs=[6 30]`), or
- reduce cycles (e.g., `cycles=[2 0.5]`), or
- lengthen epochs

`analysis.tf_transform` includes safeguards that may auto-adjust the lowest frequency with a warning.

### 5.2 Baseline normalization

Baseline correction in TF is applied on the TF time grid:

- pick a baseline window that exists in `Out_tfd.meta.times`
- use `'norm_type','decibel'` for many cognitive ERP-style analyses

### 5.3 Total vs evoked vs induced

If you need induced power:

- run `analysis.tf_transform(..., 'compute_induced', true)`

This adds:

- `evoked_power` (TF of the trial-average ERP)
- `induced_power` (total - evoked)

### 5.4 Prefer subject-level contrasts for statistics

For inference, prefer:

- `analysis.tf_contrast_maps` / `analysis.tf_contrast_maps_between`

because they preserve per-subject variability and enable proper stats.

`analysis.tf_band_stats` now uses the stored subject-level contrast maps directly.
That means ROI/band/window statistics preserve the contrast's metric (for example
`power` vs `induced_power`) and design (`within`, `between`, or `diff_in_diff`).
Build contrasts with `analysis.tf_contrast_maps` or
`analysis.tf_contrast_maps_between` before running band-level statistics.

---

## 6) Common Pitfalls and Fixes

### "newtimef not found"

Fix:

- Ensure EEGLAB is on the MATLAB path (`setup_env()`), and that `newtimef` is available.

### "Statistics Toolbox required"

Fix:

- Install Statistics and Machine Learning Toolbox, or skip stats and export features for external stats.

### Cache incompatible after parameter changes

Fix:

- Use `analysis.tf_cache_is_compatible` and recompute when needed.

---

## 7) Pointers to Real Examples in This Repo

- TF end-to-end example (with caching, contrasts, stats, features):
  - `test/analysis_tf_test.m`
