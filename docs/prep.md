# EEGflow `+prep` Module Guide (EEG Preprocessing)

This document explains how to use EEGflow's `+prep` module to preprocess EEG recordings.
It is written against the current code in `+prep/` and focuses on:

1. What each `+prep` operation does
2. What parameters it accepts (and what they mean)
3. Practical, end-to-end preprocessing recipes for resting-state and ERP/task data

---

## 0) Where `+prep` Fits in EEGflow

In EEGflow, a typical workflow is:

1. **Preprocess / clean raw EEG** using `+prep` (filtering, line noise, bad channels, ICA/IC rejection, epoching)
2. **Compute resting-state features** using `+rest` (PSD, connectivity, source features, graphs)
3. **Run ERP / TF analysis** using `+analysis` (epoch extraction, ERPs, contrasts, stats, time-frequency)

`+prep` is built around EEGflow's "state + pipeline" design:

```matlab
state = prep.<op>(state, args, meta);
```

where:

- `state.EEG` is an EEGLAB dataset struct.
- each op updates `state` in-place and appends to `state.history`.
- a `flow.Pipeline` can run many ops as a reproducible workflow from a JSON config.

---

## 1) Dependencies and Setup

### Required

- **MATLAB**
- **EEGLAB**

### Common optional dependencies (used by specific ops)

- **CleanLine** (EEGLAB plugin): used by `prep.remove_powerline` when `Method='cleanline'`
- **ICLabel** (EEGLAB plugin): used by `prep.remove_bad_ICs` when `ICLabelOn=true`
- **FASTER**: used by `prep.remove_bad_channels`, `prep.remove_bad_epoch`, `prep.remove_bad_ICs` (FASTER metrics)
- **EGI MFF Import** (EEGLAB plugin): used by `prep.load_mff`

What happens if a dependency is missing:

- If CleanLine is missing, `prep.remove_powerline(Method='cleanline')` will error. Switch to `Method='notch'`.
- If ICLabel is missing, `prep.remove_bad_ICs(ICLabelOn=true)` will error. Set `ICLabelOn=false`.
- If FASTER is missing, any FASTER-based detectors will error. Disable the relevant toggles.

### Environment variables (recommended)

EEGflow ships a helper `setup_env()` in `utils/setup_env.m`. It expects:

- `EEGFLOW_ROOT`: path to this repo
- `EEGLAB_ROOT`: path to your EEGLAB folder
- `FASTER_ROOT`: path to your FASTER folder

Example:

```matlab
setenv('EEGFLOW_ROOT', 'Z:\matlab_toolbox\EEGflow');
setenv('EEGLAB_ROOT',  'Z:\matlab_toolbox\eeglab2023.1');
setenv('FASTER_ROOT',  'Z:\matlab_toolbox\FASTER');

addpath(genpath(getenv('EEGFLOW_ROOT')));
setup_env(); % validates env vars + adds paths
```

Notes:

- `setup_env()` also applies small path hygiene (e.g., avoiding a common `extract.m` shadowing issue).
- Many `+prep` steps call EEGLAB functions; EEGLAB must be on the MATLAB path.

---

## 2) Quickstart: Run Preprocessing on One Recording

EEGflow includes a template JSON prep config at `config_template/prep_config.json`.

The usual pattern is:

1. Load config (`flow.load_cfg`)
2. Fill IO/log fields (`prep.setup_io`)
3. Build pipeline (`prep.build_pipeline`)
4. Run (`pipe.run`)

Minimal script:

```matlab
clear; clc;

% --- Environment ---
setenv('EEGFLOW_ROOT', 'Z:\matlab_toolbox\EEGflow');
setenv('EEGLAB_ROOT',  'Z:\matlab_toolbox\eeglab2023.1');
setenv('FASTER_ROOT',  'Z:\matlab_toolbox\FASTER');

repoRoot = getenv('EEGFLOW_ROOT');
addpath(genpath(repoRoot));
setup_env();

% --- Config + IO ---
cfg = flow.load_cfg(fullfile(repoRoot, 'config_template', 'prep_config.json'));

inDir = fullfile(repoRoot, 'test', 'data', 'raw');   % change to your raw folder
outDir = fullfile(repoRoot, 'test', 'out', 'prep');  % change to your output folder
if ~isfolder(outDir), mkdir(outDir); end

% Choose a file (example: regex search)
[paths, names] = filesearch_regexp(inDir, '^sub-.*\\.set$', true);
assert(~isempty(names), 'No .set files found.');
inPath = paths{1};
inFile = names{1};

cfg = prep.setup_io(cfg, ...
  'InputPath', inPath, ...
  'InputFilename', inFile, ...
  'OutputPath', outDir, ...
  'Suffix', '_prep', ...
  'DeleteExistingLogs', false);

% --- Build + run ---
[pipe, state0] = prep.build_pipeline(cfg); %#ok<ASGLU>
pipe.setLogger(@(msg) fprintf('%s\\n', msg), @(msg) fprintf(2, '%s\\n', msg));
[stateOut, report] = pipe.run('stop_on_error', true); %#ok<ASGLU>
assert(report.ok);
```

---

## 3) Core Data Structures

### 3.1 `cfg` (pipeline config)

The JSON schema is the same concept as in `README.md`:

- `cfg.steps`: array of steps, each with:
  - `id`, `name`
  - `op` (string)
  - `args` (struct)

Example step:

```json
{ "id":"S002", "name":"Filter", "op":"filter", "args": { "LowCutoff":0.5, "HighCutoff":30 } }
```

### 3.2 `prep.setup_io`

`prep.setup_io` is a convenience helper that:

- sets `cfg.Output.filename` based on the input filename and `Suffix`
- creates output/log directories
- injects `filename/filepath` into `load_*` and `save_*` steps
- injects `LogFile` and `LogPath` into steps that use logging/plot output

This keeps your JSON config portable (you don't hardcode per-subject file paths in the JSON).

### 3.3 `state`

Most ops expect:

- `state.EEG`: the current EEGLAB dataset
- `state.cfg`: config snapshot

and they update:

- `state.EEG`: modified dataset
- `state.history`: append records of what ran + summary outputs

### 3.4 Logging: `LogFile` and `LogPath`

Many `+prep` ops accept:

- `LogFile`: a text log file where the step writes messages (and the pipeline logger also prints them)
- `LogPath`: an output folder used by steps that write QC plots/files

`prep.setup_io` typically creates:

- `cfg.LogFile = <OutputPath>/<basename+suffix>.log`
- `cfg.error_LogFile = <OutputPath>/<basename+suffix>_error.log`
- `LogPath = <OutputPath>/<basename+suffix>/` (a per-recording folder)

---

## 4) Operation Reference (What Each Does + Parameters)

This section documents the public operations in `+prep/`.
For full details, also check each function header or run `help prep.<op>`.

### 4.1 `prep.build_pipeline`

**What it does**

- Builds a `flow.Pipeline` from a config struct or JSON file path.
- Resolves ops through a registry (op string -> function handle).

**Signature**

```matlab
[pipe, state0, cfg] = prep.build_pipeline(cfgOrJsonPath);
```

### 4.2 `prep.setup_io`

**What it does**

- Fills `cfg.Input`, `cfg.Output`, `cfg.LogFile`, and injects defaults into step args.

**Signature**

```matlab
cfg2 = prep.setup_io(cfg, 'InputPath', ..., 'InputFilename', ..., 'OutputPath', ...);
```

**Key options**

- `Suffix` (default `'_prep'`)
- `OutputBaseName` (override basename)
- `DeleteExistingLogs` (default `true`)
- `LogFileTargets`, `LogPathTargets` (control which cfg subfields get injected)

### 4.3 `prep.load_set`

Loads an EEGLAB `.set` file into `state.EEG`.

Key args:

- `filename`, `filepath`

### 4.4 `prep.load_mff`

Loads an EGI `.mff` bundle into `state.EEG` using EEGLAB `pop_mffimport`.

Key args:

- `filename`, `filepath`

### 4.5 `prep.save_set`

Saves `state.EEG` as an EEGLAB `.set`.

Key args:

- `filename`, `filepath`

### 4.6 `prep.downsample`

Downsamples via EEGLAB `pop_resample`.

Key args:

- `Rate` (default `250`)

### 4.7 `prep.filter`

High-pass / low-pass FIR filtering via `pop_eegfiltnew`.

Key args:

- `LowCutoff` (default `-1`, disabled if `<=0`)
- `HighCutoff` (default `-1`, disabled if `<=0`)

### 4.8 `prep.remove_powerline`

Line noise removal:

- `Method='cleanline'` (default): `pop_cleanline`
- `Method='notch'`: sequential FIR notch filters via `pop_eegfiltnew`

Key args:

- `Freq` (default `50`)
- `NHarm` (default `3`)
- `BW` (default `2`, notch half-bandwidth)

### 4.9 `prep.crop_by_markers`

Crops continuous data between two event markers with optional padding.

Key args:

- `StartMarker`, `EndMarker`
- `PadSec`

### 4.10 `prep.insert_relative_markers`

Inserts new markers at fixed offsets relative to a reference event.

Key args:

- `ReferenceMarker`
- `StartOffsetSec`
- `DurationSec` or `EndOffsetSec`
- `NewStartMarker`, `NewEndMarker`

### 4.11 `prep.edit_chantype`

Assigns `EEG.chanlocs(i).type` as `'EEG'|'EOG'|'ECG'|'OTHER'`.

Key args:

- `EOGLabel`, `ECGLabel`, `OtherLabel`

### 4.12 `prep.remove_bad_channels`

Detects bad channels using one or more detectors and then:

- removes them (`Action='remove'`, default), or
- flags them (`Action='flag'`)

Detectors include:

- EEGLAB `pop_rejchan` measures: kurtosis/probability/spectrum
- FASTER channel properties
- CleanRaw-style channel/flatline/noise parameters (if available)

Key args:

- `Action` (`'remove'|'flag'`)
- `ExcludeLabel` (channels excluded from detection)
- `KnownBadLabel` (always include as bad)
- toggles: `Kurtosis`, `Probability`, `Spectrum`, `FASTER_*`, `CleanRaw_*`

Outputs written into `EEG.etc.EEGdojo` include detector results and summaries.

### 4.13 `prep.remove_bad_ICs`

Runs ICA (if needed) and rejects artifactual components.

Key args:

- `FilterICAOn` / `FilterICALocutoff` (high-pass for ICA)
- `ICAType` (default `'runica'`)
- `ICLabelOn` / `ICLabelThreshold`
- `FASTEROn` / `EOGChanLabel`
- `DetectECG` / `ECG_Struct` / `ECGCorrelationThreshold`

### 4.14 `prep.remove_bad_epoch`

Removes bad epochs from epoched data and maintains trial ID traceability.

Key args:

- `Autorej` / `Autorej_MaxRej` (EEGLAB `pop_autorej`)
- `FASTER` (FASTER epoch properties)

### 4.15 `prep.interpolate`

Interpolates removed channels using `EEG.urchanlocs` (spherical interpolation).

Requirement:

- `EEG.urchanlocs` must exist (typically created before channel removal).

### 4.16 `prep.interpolate_bad_channels_epoch`

Detects and interpolates bad channels *per epoch* (useful for transient artifacts).

Key args:

- `ExcludeLabel`

### 4.17 `prep.reref`

Average re-reference via `pop_reref`, with optional excluded labels.

Key args:

- `ExcludeLabel`

### 4.18 `prep.remove_channels`

Removes channels by index and/or label.

Key args:

- `ChanIdx`
- `Chan2remove`

### 4.19 `prep.select_channels`

Keeps only selected channels by index and/or label.

Key args:

- `ChanIdx`
- `ChanLabels`

### 4.20 `prep.correct_baseline`

Baseline correction via `pop_rmbase` (mainly for epoched data).

Key args:

- `BaselineWindow` (ms), e.g. `[-200 0]`

### 4.21 `prep.segment_task`

Epochs continuous task data around markers via `pop_epoch`.

Key args:

- `Markers` (cellstr)
- `TimeWindow` (ms), e.g. `[-200 800]`

### 4.22 `prep.segment_rest`

Segments resting-state blocks (EC/EO) into overlapping fixed-length epochs.

Key args:

- `BlockLabel` (default `"EC"`)
- `StartCode`, `EndCode` (or `BlockDurSec` if no `EndCode`)
- `TrimStartSec`, `TrimEndSec`
- `EpochLength` (ms), `EpochOverlap` (0..1)
- `PreserveICA` (default `true`): keep ICA fields across block splitting/merge

### 4.23 `prep.register_new_op`

Creates a prep registry (or updates an existing registry) to add custom steps.

---

## 5) Tutorial: Practical Preprocessing Recipes

### 5.1 Resting-state (EC/EO) preprocessing (typical)

Common goals:

- remove slow drift and muscle noise (filtering)
- remove line noise harmonics
- detect and remove bad channels
- average reference
- ICA artifact correction
- epoch into fixed-length windows for later `+rest` analysis

Typical step order (high level):

1. `load_set` / `load_mff`
2. `downsample` (optional)
3. `remove_powerline`
4. `filter` (e.g., 0.5-30 Hz for cleaning; later analyses may use different bands)
5. `crop_by_markers` (if your recording contains extra time before/after the rest block)
6. `remove_bad_channels` (remove)
7. `reref`
8. `remove_bad_ICs`
9. `interpolate` (restore removed channels)
10. `segment_rest` (e.g., 2 s epochs, 50% overlap)
11. `remove_bad_epoch` (optional)
12. `save_set`

### 5.2 ERP/task preprocessing (typical)

Differences vs resting-state:

- You usually want to preserve event structure carefully.
- You often baseline-correct after epoching (or during epoch extraction).

Typical step order:

1. `load_set`
2. `remove_powerline`
3. `filter` (often 0.1-30 Hz or 0.5-30 Hz depending on your ERP needs)
4. `remove_bad_channels`
5. `reref`
6. `remove_bad_ICs`
7. `interpolate`
8. `segment_task` (epoch around task markers)
9. `correct_baseline` (e.g., `[-200 0]`)
10. `remove_bad_epoch` (optional)
11. `save_set`

---

## 6) Common Pitfalls and Fixes

### "Function pop_cleanline not found"

Cause:

- CleanLine plugin not installed / not on path.

Fix:

- Install CleanLine, or set `remove_powerline` to `Method='notch'`.

### "ICLabel not found"

Fix:

- Install ICLabel, or set `ICLabelOn=false` in `remove_bad_ICs`.

### "FASTER functions not found"

Fix:

- Add your `FASTER_ROOT` and run `setup_env()`, or disable the FASTER toggles.

### Markers not found in `segment_task` / `crop_by_markers` / `segment_rest`

Fix:

- Inspect `unique({EEG.event.type})` to confirm event codes and their types (string vs numeric).
- In many BDF/BrainVision datasets, event types can be numeric; EEGflow ops defensively convert to strings where needed, but your config must still match what is in the dataset.

---

## 7) Pointers to Real Examples in This Repo

- End-to-end preprocessing script:
  - `test/prep_end_to_end.m`
- Preprocessing JSON template:
  - `config_template/prep_config.json`
- Utility step tests:
  - `test/prep_test_all_utils.m`
