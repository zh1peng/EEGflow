# EEGflow ERP Analysis Guide (`+analysis`)

This document explains how to run ERP analysis with EEGflow's `+analysis` module.
It focuses on:

1. How to build an ERP dataset container from many `.set` files
2. How to compute subject ERPs, grand averages, contrasts, and stats
3. How to plot and extract ERP features for downstream statistics

This guide is written against the current code in `+analysis/`.
Current ERP module version: `analysis.get_version()` (this release: `0.6.0`).

---

## 0) Where ERP Analysis Fits in EEGflow

Typical workflow:

1. Preprocess each recording using `+prep` and save cleaned `.set`
2. Build a study-level epoch container using `analysis.extract_epoch`
3. Create an `analysis.Dataset` and `analysis.init_state`
4. Define groups, conditions, ROIs, and time windows
5. Compute ERPs, grand averages (GA), contrasts, statistics, plots, and feature tables

---

## 1) Dependencies and Setup

### Required

- **EEGLAB** (for `.set` loading and optional plotting via `topoplot`)

### Optional

- **Statistics and Machine Learning Toolbox**
  - required for `analysis.erp_compute_stats` when using `ttest`, `ttest2`, and `mafdr` (FDR correction)
  - required for `analysis.erp_compute_erps(method='trimmed')` (uses `trimmean`)

### Recommended setup

```matlab
setenv('EEGFLOW_ROOT', 'Z:\matlab_toolbox\EEGflow');
setenv('EEGLAB_ROOT',  'Z:\matlab_toolbox\eeglab2023.1');
setenv('FASTER_ROOT',  'Z:\matlab_toolbox\FASTER');

addpath(genpath(getenv('EEGFLOW_ROOT')));
setup_env();
```

---

## 2) Quickstart: End-to-End ERP Example

This example follows the same pattern as `test/analysis_erp_test.m`.

### 2.1 Extract epochs from many `.set` files

`analysis.extract_epoch` searches a folder for `.set` files, loads them, optionally applies light preprocessing, and epochs around markers.

```matlab
dataset_path = fullfile(getenv('EEGFLOW_ROOT'), 'test', 'data', 'prep'); % change to your data folder

Out = analysis.extract_epoch( ...
  'study_path',    dataset_path, ...
  'searchstring',  '^sub-.*_eeg_prep.set$', ...
  'subject_parser','(?<sub>sub-[^_]+)', ...
  'epoch_window',  [-200 1000], ...
  'baseline',      [-200 0], ...
  'aliases',       {'10','win_cue'; '20','loss_cue'; '30','neut_cue'}, ...
  'markers',       {'10','20','30'} );

ds = analysis.Dataset(Out);
fprintf('ERP module version: v%s\n', analysis.get_version());

% Dataset is a value class: assign merge output
ds = ds.merge('cue_all', {'win_cue','loss_cue','neut_cue'});
```

### 2.2 Create state, define selections, compute ERP results

```matlab
conditions = {'win_cue','loss_cue','neut_cue'};
roi_labels = {'P5','P6','POz','PO3','PO4','PO5','PO6','PO7','PO8','Oz','O1','O2'};
p300_window = [300 600]; % ms

state = analysis.init_state(ds);
state = analysis.define_group(state, struct('name','AllSubjects','subjects',{ds.get_subjects()}));
state = analysis.select_conditions(state, struct('conditions',{conditions}));
state = analysis.define_roi(state, struct('name','Pz_ROI','labels',{roi_labels}));
state = analysis.define_time_window(state, struct('name','P300','range',p300_window));

state = analysis.erp_compute_erps(state, struct('method','mean'));
state = analysis.erp_compute_ga(state, struct());
```

### 2.3 Plot GA ERPs and topographies

```matlab
analysis.erp_plot_erp(state, struct('target','Pz_ROI','smoothing_factor',1,'show_error','se'), struct());
analysis.erp_plot_topo(state, struct('time_window','P300'), struct());
```

### 2.4 Define a contrast and compute stats

```matlab
state = analysis.erp_define_contrast(state, struct( ...
  'name','win_vs_neut', ...
  'pos_term', {{'AllSubjects','win_cue'}}, ...
  'neg_term', {{'AllSubjects','neut_cue'}}));

state = analysis.erp_compute_stats(state, struct( ...
  'contrast','win_vs_neut', ...
  'roi','Pz_ROI', ...
  'alpha',0.05, ...
  'mcc','none')); % or 'fdr'

analysis.erp_plot_contrast(state, struct( ...
  'contrast','win_vs_neut', ...
  'target','Pz_ROI', ...
  'show_sig',true, ...
  'show_diff',false), struct());
```

### 2.5 Extract ERP features (table output)

```matlab
[state, T] = analysis.erp_extract_feature(state, struct( ...
  'roi','Pz_ROI', ...
  'time_window','P300', ...
  'feature_func','mean')); % 'mean'|'median'|'peak'|'latency' or a function handle
```

`T` contains per-subject rows that you can export with `writetable` and analyze in R/Python/MATLAB.

### 2.6 Two-group pattern (between-group contrast)

```matlab
subs = ds.get_subjects();
state2 = analysis.init_state(ds);
state2 = analysis.define_group(state2, struct('name','Group1','subjects',{subs(1:3)}));
state2 = analysis.define_group(state2, struct('name','Group2','subjects',{subs(4:5)}));
state2 = analysis.select_conditions(state2, struct('conditions',{conditions}));
state2 = analysis.define_roi(state2, struct('name','Pz_ROI','labels',{roi_labels}));
state2 = analysis.define_time_window(state2, struct('name','P300','range',p300_window));

state2 = analysis.erp_compute_erps(state2, struct('method','mean'));
state2 = analysis.erp_compute_ga(state2, struct());

state2 = analysis.erp_define_contrast(state2, struct( ...
  'name','G1_vs_G2_win', ...
  'pos_term', {{'Group1','win_cue'}}, ...
  'neg_term', {{'Group2','win_cue'}}));

state2 = analysis.erp_compute_stats(state2, struct('contrast','G1_vs_G2_win','roi','Pz_ROI'));
analysis.erp_plot_contrast(state2, struct('contrast','G1_vs_G2_win','target','Pz_ROI','show_sig',true), struct());
```

---

## 3) Core Data Structures

### 3.1 `Out` from `analysis.extract_epoch`

`Out` is a study container with:

- `Out.meta`: shared metadata across subjects/conditions
  - includes `toolbox_version`, `trialN`, and `warnings`
- `Out.sub_*`: one field per subject (or subject-session key)
  - each condition is stored as a `(chan x time x trials)` matrix

### 3.2 `analysis.Dataset`

`ds = analysis.Dataset(Out)` wraps the `Out` struct and exposes:

- `ds.get_subjects()`
- `ds.get_conditions()`
- `ds.get_data(subject, condition)` returning `(chan x time x trials)`
- `ds.chanlocs`, `ds.times`, `ds.fs`

### 3.3 `state` (`analysis.init_state`)

`analysis.init_state(ds)` creates:

- `state.Selection.*`:
  - `Groups`: struct mapping name -> subject list
  - `Conditions`: cellstr list
  - `ROIs`: struct mapping name -> channel labels
  - `TimeWindows`: struct mapping name -> `[start end]` ms
- `state.Results.*`:
  - `ERPs`: per-subject ERPs
  - `GA`: grand averages per group and condition
  - `SubjectContrasts`: subject-level difference waves and stats
  - `Contrasts`: contrast definitions and stats
  - `Features`: extracted feature tables

---

## 4) Function Reference (ERP)

### 4.1 `analysis.extract_epoch`

**What it does**

- Finds `.set` files under `study_path`
- Loads each file (`pop_loadset`)
- Optional inline operations: channel include/exclude, reref, filter, resample
- Epochs around `markers` into `(chan x time x trials)`
- Optional baseline correction
- Returns a single `Out` struct

**Signature**

```matlab
Out = analysis.extract_epoch('study_path', ..., 'markers', {...}, ...);
```

Key parameters:

- `study_path` (required)
- `markers` (required), `aliases` (optional marker->condition mapping)
- `epoch_window` (ms), `baseline` (ms)
- `searchstring`, `recursive`, `subject_parser`

### 4.2 `analysis.init_state`

```matlab
state = analysis.init_state(ds);
```

### 4.3 Selection helpers

- `analysis.define_group(state, struct('name',..., 'subjects',{...}))`
- `analysis.select_conditions(state, struct('conditions',{...}))`
  - selection is case-insensitive and preserves user-provided order
- `analysis.define_roi(state, struct('name',..., 'labels',{...}))`
  - channel matching is case-insensitive
- `analysis.define_time_window(state, struct('name',..., 'range',[start end]))`
  - window must overlap dataset time range

### 4.4 Dataset condition merge

- `ds = ds.merge('new_cond', {'condA','condB',...})`
  - concatenates source trials along the 3rd dimension
  - source conditions are preserved; overwrite is not allowed
  - strict mode: missing condition/empty data/shape mismatch raises error
  - updates `meta.conditions`, `meta.trialN`, `meta.summary`, and `meta.derived_conditions`

### 4.5 ERP computation

- `analysis.erp_compute_erps(state, struct('method','mean'|'median'|'trimmed', 'percent',5))`
  - computes subject-level ERPs by averaging across trials
  - note: `method='trimmed'` uses `trimmean` (Statistics Toolbox)
- `analysis.erp_compute_ga(state, struct())`
  - computes group-level grand averages from subject ERPs

### 4.6 Contrasts and stats

- `analysis.erp_define_contrast(state, struct('name',..., 'pos_term',{{group,cond}}, 'neg_term',{{group,cond}}))`
- `analysis.erp_compute_stats(state, struct(...))`
  - default: computes waveform statistics across the full ERP epoch
  - `time_window` is an explicit override if you want to restrict the inferential range
  - args:
    - `contrast` (name)
    - `roi` (optional ROI name; if empty, stats across channels)
    - `alpha` (default 0.05)
    - `mcc` (`'none'` or `'fdr'`)
    - `time_window` (optional `[start end]` ms)
  - significance output is point-wise t-test significance segments (not cluster-permutation inference)

- `analysis.erp_compute_subject_contrast(state, struct(...))`
  - args: `name`, `pos_term={{group,condA}}`, `neg_term={{group,condB}}`
  - within-group only (strict)
  - computes subject-level difference waves and stores them in `state.Results.SubjectContrasts`

- `analysis.erp_compute_subject_contrast_stats(state, struct(...))`
  - default: computes waveform statistics across the full ERP epoch
  - `time_window` is an explicit override if you want to restrict the inferential range
  - args: `contrast`, `roi` (optional), `alpha`, `mcc`, `time_window` (optional)
  - one-sample t-test of subject-level difference waves against zero

### 4.7 Plotting

- `analysis.erp_plot_erp(state, struct('target',..., 'smoothing_factor',1, 'show_error','se'|'sd'|'std'|'none', ...))`
  - canonical GA ERP plotting entry point
  - ERP line plots use EEG convention: negative up / positive down
- `analysis.erp_plot_contrast(state, struct('contrast',..., 'target',..., 'show_sig',true, ...))`
  - if `time_window` is provided, it only changes the displayed x-axis limits
  - significance shading comes from the stats already stored in `Stats.h`
- `analysis.erp_plot_subject_contrast(state, struct('contrast',..., 'target',..., 'show_sig',true, ...))`
  - same rule as `erp_plot_contrast`: plot window is display-only, shading comes from `Stats.h`
- `analysis.erp_plot_topo(state, struct('time_window',...))`
  - `time_window` here is a named selection window used for topography lookup

### 4.8 Feature extraction

- `[state, T] = analysis.erp_extract_feature(state, struct(...))`
  - args:
    - `roi` (required)
    - `time_window` (required)
    - `feature_func` (`'mean'|'median'|'peak'|'latency'` or function handle)
    - `peak_polarity` (`'max'|'min'`)

- `[state, T] = analysis.erp_extract_subject_contrast_feature(state, struct(...))`
  - args: `contrast`, `roi`, `time_window`, `feature_func`, `peak_polarity`
  - returns one row per subject for a subject-level ERP contrast

---

## 5) Tutorial: ERP Analysis Workflow (Practical Notes)

### 5.0 Preprocessing vs analysis extraction

`analysis.extract_epoch` can filter/resample/reref as a convenience, but for most studies you should:

- do artifact cleaning in `+prep` (bad channels, ICA, interpolation, etc.)
- use `analysis.extract_epoch` mainly for *epoching + packaging* into an analysis-friendly struct

### 5.1 Marker naming and aliases

Many datasets use numeric event codes (e.g., `10`, `20`, `30`) but you want readable condition names.
Use `aliases` in `analysis.extract_epoch` to map markers to canonical condition names.
You can map multiple markers to one condition (e.g., `10 -> salience_cue`, `20 -> salience_cue`); extracted trials are concatenated into that condition.

### 5.2 ROI definitions

`analysis.define_roi` accepts channel labels. It validates them against `ds.chanlocs` and drops missing labels.

Good practice:

- define ROIs based on your hypothesis and sensor layout
- keep ROIs stable across studies to reduce researcher degrees of freedom

### 5.3 Time windows

Time windows are in milliseconds in dataset time coordinates (from `extract_epoch`).

Example:

- `P300 = [300 600]`
- `N170 = [140 200]`

### 5.4 Contrasts and stats

ERP contrasts are defined between two GA terms:

- within-group: same group, two conditions
- between-group: two groups, same (or different) conditions

`analysis.erp_compute_stats` chooses a paired design only when:

- `pos_group == neg_group`, and
- the subject lists for the two terms are identical

If some subjects are missing one condition, it uses the intersection for paired tests (with a warning), and requires at least 2 paired subjects.

---

## 6) Common Pitfalls and Fixes

### "Statistics Toolbox required"

Cause:

- `analysis.erp_compute_stats` uses `ttest`, `ttest2`, and optionally `mafdr`.

Fix:

- Install the Statistics and Machine Learning Toolbox, or skip stats and export features for external stats.

### "ROI has no valid channels"

Fix:

- Confirm channel labels in `ds.chanlocs`.
- Adjust ROI labels (matching is case-insensitive, but label spelling must still be correct).

### Conditions not found

Fix:

- Confirm `aliases` mapping and `markers` match your EEG events.
- Check `ds.conditions` after `analysis.Dataset(Out)`.

---

## 7) Pointers to Real Examples in This Repo

- ERP end-to-end example:
  - `test/analysis_erp_test.m`
- Epoch extraction entry point:
  - `+analysis/extract_epoch.m`
