# EEGflow `+rest` Module Guide (Resting-State EEG)

This document explains how to use EEGflow's `+rest` module to compute and visualize resting-state EEG features.
It is written against the current code in `+rest/` and focuses on:

1. What each `+rest` function does
2. What parameters it accepts (and what they mean)
3. A practical, end-to-end tutorial for resting-state EEG processing and analysis

---

## 0) Where `+rest` Fits in EEGflow

In EEGflow, the typical workflow is:

1. **Preprocess / clean EEG** using `+prep` (filtering, bad channels/epochs/ICs, re-reference, etc.)
2. **Segment resting-state blocks and epoch them** (e.g., eyes-closed "EC" into 2 s epochs)
3. **Compute resting-state features** using `+rest` (PSD, peak alpha frequency, aperiodic component, source-space connectivity, graph measures)
4. **Plot + QC** using `+rest.plot_*`
5. **Export features** (optional) using `+rest.features2csv*` and run group statistics elsewhere (R/Python/MATLAB)

`+rest` is designed around EEGflow's "state + middleware" convention:

```matlab
state = rest.compute_all_features(state, args, meta);
```

where `state.EEG` is an EEGLAB struct and the step updates `state.rest.*`.

---

## 1) Dependencies and Coordinate Assumptions

### Required for most workflows

- **EEGLAB**: for `.set` datasets and the EEGLAB `EEG` struct.
- **FieldTrip**: for spectral analysis, beamforming, virtual channels, connectivity, and many plots.

### Optional

- **GRETNA**: only required if you enable graph measures (`ComputeGraph=true`).
- **AEC**: EEGflow includes an orthogonalized AEC implementation (`rest.aecConnectivity`, Hipp et al. 2012).
  It does not require Brainstorm or DISCOVER-EEG. If `hilbert()` is available it will be used; otherwise an internal analytic-signal fallback is used.

### Coordinate system

The default demo atlas shipped with EEGflow is a Schaefer2018 centroid CSV in **MNI RAS** coordinates (mm):

`resources/atlas/Schaefer2018_100Parcels_7Networks_order_FSLMNI152_1mm.Centroid_RAS.csv`

You can get its absolute path via:

```matlab
atlasPath = rest.atlas_default_path();
```

Note: the shipped Schaefer centroid CSV is copied from DISCOVER-EEG (CC BY 4.0); see `resources/atlas/README.md`.

The default FieldTrip head model template is also MNI-ish in mm:

`$FIELDTRIP_ROOT/template/headmodel/standard_bem.mat`

For source-space results to be meaningful, your:

- head model (`HeadModelPath` / `HeadModel`)
- electrode positions (`TemplateElecFile` / `Elec` / `EEG.chanlocs`)
- atlas / source positions (`AtlasPath` / `SourcePos`)

must all be consistent in **coordinate system** and **units**.

---

## 2) Quickstart: Run Rest Features on One Subject

This is a script-style minimal example (no JSON needed). It assumes you have an already-epoched resting dataset (epochs = trials).

```matlab
clear; clc;

% --- Paths / env ---
setenv('EEGFLOW_ROOT', 'Z:\matlab_toolbox\EEGflow');
setenv('EEGLAB_ROOT',  'Z:\matlab_toolbox\eeglab2023.1');
setenv('FASTER_ROOT',  'Z:\matlab_toolbox\FASTER');
setenv('FIELDTRIP_ROOT','Z:\matlab_toolbox\fieldtrip-20250114');
setenv('GRETNA_ROOT',  'Z:\matlab_toolbox\GRETNA-2.0.0_release'); % optional

repoRoot = getenv('EEGFLOW_ROOT');
addpath(genpath(repoRoot));
setup_env();

ftRoot = getenv('FIELDTRIP_ROOT');
addpath(ftRoot); ft_defaults;

% --- Inputs ---
inFile = fullfile(repoRoot,'test','data','rest','sub-113_task-rest_run-01_eeg_prepEC.set');
outDir = fullfile(repoRoot,'test','out','rest_quickstart');
if ~isfolder(outDir), mkdir(outDir); end

% FieldTrip templates
headModelPath = fullfile(ftRoot,'template','headmodel','standard_bem.mat');
elecFile      = fullfile(ftRoot,'template','electrode','standard_1005.elc');
atlasPath     = rest.atlas_default_path();

% Keep it fast: alpha only, first 30 ROIs
atlas = rest.atlas_load(atlasPath);
SourcePos = atlas.pos(1:30,:);
FreqBand = struct('alpha',[8 12]);

% --- Build + run a rest pipeline ---
cfg = struct();
cfg.steps = [
  struct('id','S001','name','Load','op','load_set', ...
    'args', struct('filename', 'sub-113_task-rest_run-01_eeg_prepEC.set', ...
                  'filepath', fileparts(inFile))), ...
  struct('id','S002','name','RestFeatures','op','compute_all_features', ...
    'args', struct( ...
      'OutputPath', outDir, ...
      'OutputBaseName', 'sub-113', ...
      'SaveMat', true, ...
      'KeepInState', false, ...
      'FreqBand', FreqBand, ...
      'RemoveAperiodic', true, ...
      'AperiodicFitRange', [2 40], ...
      'ComputeSource', true, ...
      'ComputeDwpli', true, ...
      'ComputeAec', true, ...
      'ComputeGraph', false, ...
      'ComputeSourcePower', true, ...
      'HeadModelPath', headModelPath, ...
      'TemplateElecFile', elecFile, ...
      'AtlasPath', atlasPath, ...
      'SourcePos', SourcePos, ...
      'Unit', 'mm', ...
      'AutoAddDeps', true, ...
      'FieldTripRoot', ftRoot ...
    )) ...
];

[pipe, state0] = rest.build_pipeline(cfg); %#ok<ASGLU>
[stateOut, report] = pipe.run('stop_on_error', true);
assert(report.ok);

S = load(stateOut.rest.output_file, 'res');
res = S.res;

% --- Plot ---
figDir = fullfile(outDir,'fig');
if ~isfolder(figDir), mkdir(figDir); end

f1 = rest.plot_power(res, 'Visible','off', 'Title','Sensor PSD');
exportgraphics(f1, fullfile(figDir,'psd.png'), 'Resolution', 150); close(f1);

f2 = rest.plot_connectivity(res, 'dwpli', 'Visible','off', 'Title','dwPLI');
exportgraphics(f2, fullfile(figDir,'dwpli_matrix.png'), 'Resolution', 150); close(f2);

f2b = rest.plot_connectivity(res, 'aec', 'Visible','off', 'Title','AEC');
exportgraphics(f2b, fullfile(figDir,'aec_matrix.png'), 'Resolution', 150); close(f2b);

f3 = rest.plot_power_source(res, 'Visible','off', 'Title','Source power');
exportgraphics(f3, fullfile(figDir,'source_power.png'), 'Resolution', 150); close(f3);
```

Notes:

- If your dataset is continuous, run `prep.segment_rest` (or your own epoching) before `compute_all_features`.
- If channel labels do not match the electrode template, `compute_all_features` will drop unmatched channels.

---

## 3) Core Data Structures

### 3.1 `state` (EEGflow state)

Most rest ops follow:

```matlab
state = op(state, args, meta)
```

For `rest.compute_all_features`, the required input is:

- `state.EEG`: an EEGLAB EEG struct **with epochs** (`EEG.trials >= 1`)

Key outputs:

- `state.rest.output_file`: MAT file path (if `SaveMat=true`)
- `state.rest.features`: `res` struct (if `KeepInState=true`)

### 3.2 `res` (rest feature output)

Saved to `<OutputBaseName>_rest_features.mat` as variable `res`.

Typical fields:

- `res.subid`: subject id (string)
- `res.nTrial`: number of epochs used
- `res.params`: snapshot of params used (large structs stripped)
- `res.power`: FieldTrip freq struct (sensor PSD)
- `res.bandpower`: absolute and relative sensor band-power summaries for each configured band
- `res.peakfrequency`: struct (alpha peak metrics)
- `res.aperiodic`: struct (aperiodic fit) if `RemoveAperiodic=true`
- `res.power_osc`: flattened PSD if `RemoveAperiodic=true`
- `res.peakfrequency_osc`: peak metrics on flattened PSD if `RemoveAperiodic=true`
- Per-band outputs (for each band in `res.params.FreqBand`):
  - `res.(band).source_pos`: inside-node positions (nNode x 3)
  - `res.(band).source_pow`: inside-node band power (nNode x 1) if `ComputeSourcePower=true`
  - `res.(band).dwpli_connMatrix`: (nNode x nNode) if `ComputeDwpli=true`
  - `res.(band).aec_connMatrix`: (nNode x nNode) if `ComputeAec=true`
  - `res.(band).dwpli_net_sum`, `res.(band).dwpli_node_sum`: if `ComputeGraph=true` and GRETNA available
  - `res.(band).parcellation`: if `AtlasPath` provided (used for plotting node order by network)

### 3.3 `atlas` and `parcellation`

`atlas = rest.atlas_load(csvPath)` returns:

- `atlas.pos` (nROI x 3)
- optional metadata fields: `roi_label`, `roi_name`, `hemi`, `network`

`parc = rest.atlas_make_parcellation(atlas, idx, ...)` returns:

- node reordering and network block boundaries for plotting
- `parc.order_by_network` is used by `rest.plot_connectivity`

Important limitation:

- `compute_all_features` assumes the node indices used for connectivity correspond to the row indices in `atlas`.
  - Easiest safe pattern: **do not pass `SourcePos`** and let `compute_spatial_filter` derive positions from `AtlasPath`.
  - If you pass `SourcePos` (subset), ensure your `AtlasPath` is aligned to that subset (same row order/meaning),
    otherwise network labels can be wrong.

---

## 4) Function Reference (What Each Does + Parameters)

This section documents the public functions in `+rest/`.

### 4.1 Config (JSON)

EEGflow stores pipeline parameters in JSON config files. A template is provided:

- `config_template/rest_config.json`

You can load and run it via:

```matlab
[pipe, state0] = rest.build_pipeline('config_template/rest_config.json');
[stateOut, report] = pipe.run('stop_on_error', true);
```

---

### 4.2 `rest.build_pipeline`

**What it does**

- Builds a `flow.Pipeline` configured with a **rest registry**.
- The rest registry includes:
  - `load_set`, `save_set`, `segment_rest` (reused from `+prep`)
  - `compute_all_features` (from `+rest`)

**Signature**

```matlab
[pipe, state, cfg] = rest.build_pipeline(cfgOrPath, 'State', state, 'Registry', reg);
```

**Inputs**

- `cfgOrPath`: config struct or JSON path (loaded via `flow.load_cfg`)
- `cfg.steps`: array of steps: `id`, `name`, `op`, `args`

**Options**

- `State`: initial state (default `struct()`)
- `Registry`: override registry map (default: rest registry)
- `WhenEvaluatorFn`: optional evaluator for string `when` expressions in steps

---

### 4.3 `rest.compute_all_features` (Main Entry Point)

**What it does**

Computes resting-state features in a single step:

1. Convert `state.EEG` to FieldTrip epoched format (`data.trial`)
2. Sensor-space PSD (`rest.compute_power`)
3. Alpha peak frequency (`rest.compute_peakfrequency`)
4. Optional aperiodic fit + flattened PSD (`rest.compute_aperiodic`)
5. For each band in `FreqBand` (if `ComputeSource=true`):
   - LCMV spatial filters (`rest.compute_spatial_filter`)
   - Optional per-node source power (`rest.compute_source_power`)
   - Connectivity: dwPLI (`rest.compute_dwpli`) and/or AEC (`rest.compute_aec`)
   - Optional graph metrics via GRETNA (`rest.compute_graph_measures`)
   - Optional parcellation metadata for plotting (`rest.atlas_load`, `rest.atlas_make_parcellation`)
6. Save MAT output and/or keep results in `state.rest.features`

**Signature**

```matlab
state = rest.compute_all_features(state, args, meta);
```

**Required state**

- `state.EEG` (EEGLAB struct, epoched)

**Common parameters (args)**

I/O and logging:

- `LogFile` (default `''`): append logs to a file (optional)
- `OutputPath` (default `''`): output dir (falls back to `state.cfg.Output.filepath` or `pwd`)
- `OutputBaseName` (default `''`): used in filenames (falls back to `state.cfg.Output.basename` or `EEG.setname`)
- `SaveMat` (default `true`): write `<base>_rest_features.mat`
- `KeepInState` (default `true`): store `res` in `state.rest.features`

Trial threshold:

- `MinTrials` (default `10`): preferred spelling for the minimum epoch count
- `nTrial_treshold` (default `10`): skip feature extraction if too few epochs
  - legacy spelling kept for backward compatibility; `MinTrials` wins if both are provided

Spectral params (sensor PSD):

- `PowerFreqRange` (default `[1 100]`): sensor PSD frequency range
- `PowerFreqStep` (default `FreqRes` when provided): frequency step used to build `cfg.foi`
- `PowerFoi` (default `[]`): explicit frequency vector; overrides `PowerFreqRange` / `PowerFreqStep`
- `PeakBand` (default `'alpha'` when available): band used by `compute_peakfrequency`
- `FreqRes` (default `0.1`): legacy alias for `PowerFreqStep`
- `Pad` (default `[]`): passed to `ft_freqanalysis` when non-empty
- `Taper` (default `'dpss'`): requires Signal Processing Toolbox for `dpss`; use `'hanning'` if unavailable
- `Tapsmofrq` (default `1`)
- `FreqBand` (**required**): a struct, e.g. `struct('alpha',[8 12])`

Aperiodic analysis:

- `RemoveAperiodic` (default `false`)
- `AperiodicFitRange` (default `[2 40]`)

Source / models:

- `ComputeSource` (default `true`)
- `HeadModelPath` (default `''`) or `HeadModel` (default `[]`)
- `TemplateElecFile` (default `''`) or `Elec` (default `[]`)
- `AtlasPath` (default `''`) and/or `SourcePos` (default `[]`)
- `Unit` (default `'mm'`)

Connectivity and graph:

- `ComputeDwpli` (default `true`)
- `ComputeAec` (default `true`)
- `FreqResConnectivity` (default `0.5`)
- `FailOnBandError` (default `true`): fail the pipeline if a requested per-band source/connectivity output cannot be computed
- `ComputeGraph` (default `true`, but skipped if GRETNA not found)
- `GRETNA_s1` (default `0.05`)
- `GRETNA_s2` (default `0.3`)
- `GRETNA_deltas` (default `0.02`)
- `GRETNA_n` (default `1000`)

Output size controls:

- `KeepSource` (default `false`): keeping FieldTrip `source` structs can be huge
- `ComputeSourcePower` (default `true`): store per-node power vector (`source_pow`) even when not keeping the full `source`

Atlas/network ordering (plotting convenience):

- `AtlasNetworkOrder` (default `{'Vis','SomMot','DorsAttn','SalVentAttn','Limbic','Cont','Default'}`)

Dependency auto-wiring:

- `AutoAddDeps` (default `true`)
- `FieldTripRoot` (default `''`): path used if FieldTrip functions not on path
- `GretnaRoot` (default `''`): path used if GRETNA functions not on path

**Outputs**

- Updates `state.rest.output_file` if `SaveMat=true`
- Optionally updates `state.rest.features` if `KeepInState=true`

---

### 4.4 `rest.compute_power`

**What it does**

- Computes sensor-space power spectral density (PSD) using FieldTrip `ft_freqanalysis`.
- Current implementation uses multi-taper FFT across epochs and averages (`keeptrials='no'`).
- Frequency limits are controlled by `PowerFreqRange`, `PowerFreqStep`, or `PowerFoi`.

**Signature**

```matlab
power = rest.compute_power(data, params);
```

**Inputs**

- `data`: FieldTrip epoched data (`data.trial{t} = channels x time`)
- `params.Taper`, `params.Tapsmofrq`, `params.Pad`

**Output**

- `power`: FieldTrip freq struct with `.freq` and `.powspctrm`

---

### 4.5 `rest.compute_peakfrequency`

**What it does**

- Computes peak frequency on the channel-averaged PSD within `params.PeakBand`.
- Defaults to alpha when `params.FreqBand.alpha` exists.
- Two estimates:
  - `localmax`: highest local maximum within alpha range
  - `cog`: center-of-gravity within alpha range

**Signature**

```matlab
pf = rest.compute_peakfrequency(power, params);
```

**Inputs**

- `power`: FieldTrip freq struct (`power.freq`, `power.powspctrm`)
- `params.FreqBand.alpha`: `[fmin fmax]` used as the search window

**Output**

- `pf.localmax`, `pf.cog`
- `pf.band`, `pf.range_hz`, `pf.peak_found`

### 4.5b `rest.compute_bandpower`

**What it does**

- Computes absolute and relative sensor-space band power for every band in `params.FreqBand`.
- Stores per-channel vectors plus mean summaries suitable for CSV export.

**Signature**

```matlab
bp = rest.compute_bandpower(power, params);
```

**Output**

For each band, e.g. `bp.alpha`:

- `range_hz`
- `absolute` and `relative` per-channel vectors
- `absolute_mean` and `relative_mean`

---

### 4.6 `rest.compute_aperiodic`

**What it does**

- Fits a simple aperiodic `1/f` component in log-log space per channel
  using a linear fit of `log10(power) ~ intercept + slope*log10(freq)`.
- Returns a flattened spectrum (`power_osc`) by dividing the PSD by the fitted `1/f`.

**Signature**

```matlab
[aperiodic, power_osc] = rest.compute_aperiodic(power, params);
```

**Key params**

- `params.AperiodicFitRange` (default `[2 40]` Hz)

**Outputs**

- `aperiodic.exponent = -slope` (positive exponent)
- `aperiodic.offset` (intercept at 1 Hz in log10 scale)
- `aperiodic.r2` fit quality
- `power_osc.powspctrm` flattened PSD

---

### 4.7 `rest.compute_spatial_filter`

**What it does**

- Builds an LCMV beamformer spatial filter for one band:
  - creates a source model from `SourcePos` or `AtlasPath`
  - band-pass filters data in the band
  - computes sensor covariance
  - computes leadfields
  - runs `ft_sourceanalysis(method='lcmv', keepfilter='yes')`

**Signature**

```matlab
source = rest.compute_spatial_filter(data, params, bandName);
```

**Key params**

- `params.HeadModelPath` or `params.HeadModel`
- `params.SourcePos` or `params.AtlasPath`
- `params.FreqBand.(bandName)`
- `params.Unit` (default `'mm'`)

**Output**

- `source`: FieldTrip source struct containing `.pos`, `.inside`, and spatial filters

---

### 4.8 `rest.compute_source_power`

**What it does**

- Computes a simple band-limited power estimate per inside-node by:
  - band-pass filtering sensor data
  - reconstructing virtual channels (`ft_virtualchannel`)
  - averaging mean-square amplitude across time and trials

**Signature**

```matlab
pow = rest.compute_source_power(data, source, params, bandName);
```

**Output**

- `pow`: `(nInside x 1)` power vector aligned with `source.pos(source.inside,:)`

---

### 4.9 `rest.compute_dwpli`

**What it does**

- Computes debiased weighted phase lag index (dwPLI) connectivity:
  - band-pass filter
  - virtual channel reconstruction (inside nodes)
  - multi-taper Fourier (`ft_freqanalysis(output='fourier', keeptrials='yes')`)
  - connectivity (`ft_connectivityanalysis(method='wpli_debiased')`)
  - average across frequency bins

**Signature**

```matlab
C = rest.compute_dwpli(data, source, params, bandName);
```

**Key params**

- `params.FreqResConnectivity` controls frequency bin spacing within the band

**Output**

- `C`: `(nInside x nInside)` connectivity matrix

---

### 4.10 `rest.aecConnectivity`

**What it does**

- Computes **orthogonalized** amplitude envelope correlation (AEC) connectivity (Hipp et al. 2012) on a virtual-channel time series.
- Returns a connectivity matrix **per epoch** (no averaging).
- Used internally by `rest.compute_aec`.
- Adapted from DISCOVER-EEG custom functions (CC BY 4.0; see the function docstring for attribution).

**Signature**

```matlab
Cepoch = rest.aecConnectivity(virtChan_data);
```

**Input**

- `virtChan_data`: FieldTrip-like virtual channel data struct with fields:
  - `.trial` (cell array), each trial is `(nChan x nTime)`
  - `.label` (cell array), `(nChan x 1)`

**Options (name-value)**

- `Normalize` (default `true`): divide by 0.577 (Hipp 2012) to compensate for under-estimation due to orthogonalization.
- `UseLogPower` (default `true`): correlate `log(|x|^2 + Tol)` (log power envelopes) instead of `|x|` (amplitude envelopes).
- `Tol` (default `1e-8`): small constant used inside the log transform.
- `ReplaceNonFinite` (default `true`): replace non-finite correlations with 0.
- `Verbose` (default `false`): print per-epoch timing.
- `Eps` (default `eps`): numerical stability constant used in orthogonalization.

**Output**

- `Cepoch`: `(nChan x nChan x nEpoch)` connectivity matrices per epoch.

---

### 4.11 `rest.compute_aec`

**What it does**

- Computes **orthogonalized** amplitude envelope correlation (AEC) connectivity between virtual channels (Hipp et al. 2012).
- Uses `rest.aecConnectivity` internally (adapted from DISCOVER-EEG custom functions, CC BY 4.0; see the function docstring for attribution).

**Signature**

```matlab
C = rest.compute_aec(data, source, params, bandName);
```

**Output**

- `C`: `(nInside x nInside)` connectivity matrix

---

### 4.12 `rest.compute_graph_measures`

**What it does**

- Runs GRETNA network analysis on a weighted adjacency matrix and returns:
  - global measures (`net_sum`)
  - nodal measures (`node_sum`)

**Signature**

```matlab
[net_sum, node_sum] = rest.compute_graph_measures(W, params);
```

**Key params**

- `params.GRETNA_s1`, `params.GRETNA_s2`, `params.GRETNA_deltas`, `params.GRETNA_n`

**Dependency**

- Requires `gretna_sw_batch_networkanalysis_weight` on path.

---

### 4.13 Atlas utilities: `rest.atlas_default_path`, `rest.atlas_load`, and `rest.atlas_make_parcellation`

`rest.atlas_default_path(...)`

- Returns an absolute path to a centroid CSV shipped with EEGflow (see `resources/atlas/`).

`rest.atlas_load(atlasCsvPath, ...)`

- Loads a centroid CSV as a lightweight "atlas" struct.
- Parses ROI name patterns to infer hemisphere (`LH`/`RH`) and network labels
  (Schaefer7-style by default).

Params:

- `NetworkOrder` (default Schaefer7 order)

`rest.atlas_make_parcellation(atlas, idxInAtlas, ...)`

- Builds a `parcellation` struct that groups nodes by `atlas.network`
  and produces:
  - `order_by_network` reordering indices
  - `boundary_ticks`, `label_tick_pos` for plotting network blocks

Params:

- `Pos`: override positions for the nodes (must match `idxInAtlas` ordering)
- `NetworkOrder`: desired network ordering

---

### 4.14 Plotting utilities

All plots accept a `res` struct (from `compute_all_features` output).

`rest.plot_power(res, ...)`

- Sensor PSD (and optionally band topographies if FieldTrip topoplot is available).
- Options: `Visible`, `Title`, `FreqBand`

`rest.plot_peakfrequency(res, ...)`

- Alpha-band peak frequency on PSD.
- Options: `Visible`, `Title`

`rest.plot_connectivity(res, 'dwpli'|'aec', ...)`

- Network-blocked connectivity matrices across bands.
- Uses `res.(band).parcellation` when available.
- Options: `Visible`, `Title`, `ShowNetworkLabels`

`rest.plot_power_source(res, ...)`

- Scatter plot of per-node source power across bands.
- If `SurfaceModelPath` is provided (or `res.params.SurfaceModelPath`), draws cortex mesh.
- Otherwise it falls back to drawing a light head/scalp mesh from the headmodel when available.
- Options: `Visible`, `Title`, `SurfaceModelPath`, `View`

`rest.plot_graph_measures(res, 'dwpli'|'aec', ...)`

- Visualizes nodal and global graph measures across bands (requires GRETNA outputs).
- Options: `NodeMetrics`, `GlobalMetrics`, `SurfaceModelPath`, `Visible`, `View`

`rest.plot_atlasregions(params, ...)`

- Plots atlas ROI centroids grouped by network, optionally with a head mesh background.
- Inputs: `params` struct (typically `res.params`)
- Options: `Visible`, `Title`, `View`

`rest.plot_power_measures(res, ...)`

- One-figure "Power-based measures" panel: sensor PSD + source-power topographies across bands.
- Options: `Visible`, `Title`, `FreqBand`, `SurfaceModelPath`, `View`

`rest.plot_connectivity_measures(res, ...)`

- One-figure "Functional connectivity measures" panel: dwPLI and AEC connectivity matrices side-by-side across bands.
- Options: `Measures`, `Visible`, `Title`, `ShowNetworkLabels`

`rest.plot_brain_network_measures(res, ...)`

- One-figure "Brain network measures" panel: local (nodal) graph measures across bands for dwPLI/AEC.
- Requires GRETNA outputs (`ComputeGraph=true` and GRETNA on path).
- Options: `Measures`, `NodeMetrics`, `Visible`, `Title`, `SurfaceModelPath`, `View`, `MarkerSize`

---

### 4.15 Export utilities: `rest.features2csv`, `rest.features2csv_parallel`

**What they do**

- Load one or more `<sub>_rest_features.mat` files and export a "wide" feature table to CSV.
- Exports:
  - sensor band-power summaries (`*_power_abs_mean`, `*_power_rel_mean`)
  - aperiodic summaries (`aperiodic_exponent_mean`, `aperiodic_offset_mean`, `aperiodic_r2_mean`)
  - dwPLI and AEC global (net) measures (if present)
  - dwPLI and AEC nodal measures (if present)
  - alpha peak frequency fields

**Signatures**

```matlab
rest.features2csv(matFileList, outputCSV);
rest.features2csv_parallel(matFileList, outputCSV);
```

Notes:

- These functions expect GRETNA-derived graph measure fields when exporting graph metrics.
- The exported schema is currently "flat" and can get very wide for many nodes.

---

### 4.16 `rest.register_new_op`

**What it does**

- Creates or extends a rest registry (containers.Map) with a new op mapping.

**Signature**

```matlab
reg = rest.register_new_op('my_step', @my_step);
reg = rest.register_new_op(reg, 'my_step', @my_step, 'AllowOverride', true);
```

---

## 5) Tutorial: Resting-State EEG Analysis (Practical Guide)

This section is a "workflow tutorial" rather than an API reference.

### 5.1 Define what "rest" means in your dataset

Common scenarios:

- Eyes closed (EC) vs eyes open (EO)
- Fixed-length continuous rest blocks (e.g., 2-5 minutes)
- Multiple runs or sessions

Decide early:

- Which condition(s) you will analyze (EC/EO)
- Epoch length and overlap (tradeoff between stationarity and number of samples)
- How you will handle artifacts (reject vs repair/interpolate)

### 5.2 Preprocessing (recommended)

Connectivity and peak-frequency estimates are very sensitive to preprocessing.
At minimum:

- Band-limit and remove line noise
- Remove bad channels (and interpolate)
- Remove gross artifacts (bad epochs) and ocular/muscle ICs
- Re-reference (average reference is common)

In EEGflow, this is typically done using `+prep` steps, for example:

```matlab
cfg.steps = [
  struct('id','S001','op','load_set','args', ...),
  struct('id','S010','op','filter','args', struct('LowCutoff',0.5,'HighCutoff',45)),
  struct('id','S020','op','remove_powerline','args', struct('Method','cleanline','Freq',60)),
  struct('id','S030','op','remove_bad_channels','args', struct('Action','remove','FASTER_MeanCorr',true)),
  struct('id','S040','op','remove_bad_ICs','args', struct('ICLabelOn',true,'FASTEROn',true)),
  struct('id','S050','op','reref','args', struct('ExcludeLabel',{{'VEOG','HEOG'}})),
  struct('id','S060','op','segment_rest','args', struct('BlockLabel','EC','EpochLength',2000,'EpochOverlap',0.5)),
  struct('id','S070','op','compute_all_features','args', ...),
];
```

Important:

- `rest.compute_all_features` expects *epoched* EEG. Use `prep.segment_rest` (or another epoching method) first if needed.

### 5.3 Epoching choices

Typical choices:

- 2 s epochs with 50% overlap (common in resting-state)
- 4 s epochs with no overlap (more frequency resolution, fewer epochs)

Tradeoffs:

- Longer epochs improve low-frequency resolution but are less stationary.
- More epochs improves robustness (connectivity especially).

EEGflow uses `nTrial_treshold` (default 10) to skip feature computation if you have too few usable epochs.

### 5.4 Sensor-space spectra and peak alpha frequency

The module computes:

- PSD (multi-taper)
- Peak alpha frequency (local max and center of gravity)

Interpretation tips:

- Peak alpha frequency depends on:
  - preprocessing (especially filtering and artifact removal)
  - whether you use EC vs EO
  - whether you remove aperiodic component

The `RemoveAperiodic=true` option adds:

- aperiodic exponent/offset estimates
- "oscillatory-only" flattened PSD (`power_osc`) and peak frequency (`peakfrequency_osc`)

### 5.5 Source-space reconstruction

EEGflow uses an LCMV beamformer with a template head model by default.

What you need:

- A head model (`HeadModelPath` or `HeadModel`)
- Reasonable sensor positions:
  - a matching `TemplateElecFile`, or
  - an `Elec` struct, or
  - EEGLAB `chanlocs` with valid XYZ coordinates
- A source grid:
  - `AtlasPath` (centroid CSV), or
  - `SourcePos` (explicit [n x 3] positions)

Accuracy note:

- Template head models are convenient but approximate.
- For higher validity, replace with subject-specific head models and electrode positions.

### 5.6 Connectivity (dwPLI and AEC)

dwPLI:

- Designed to reduce spurious connectivity from volume conduction by focusing on non-zero-lag phase coupling.
- Still sensitive to:
  - SNR
  - filtering choices
  - number of epochs
  - source leakage

AEC:

- Correlation of amplitude envelopes; can reflect slower co-fluctuations.
- Often computed after band-pass filtering, sometimes with orthogonalization (not done in the simple fallback).

EEGflow computes both at the source ROI level using virtual channels.

### 5.7 Graph measures (optional)

If you enable `ComputeGraph=true` and have GRETNA on your path, EEGflow will compute:

- nodal measures (per ROI)
- global measures (per band)

Graph outputs depend heavily on:

- thresholding/sparsity parameters (`GRETNA_s1`, `GRETNA_s2`, etc.)
- connectivity measure (dwPLI vs AEC)
- number and distribution of ROIs

### 5.8 QC and visualization

Recommended QC plots (all provided by `+rest`):

- Sensor PSD and topographies: `rest.plot_power`
- Connectivity matrices with network blocks: `rest.plot_connectivity`
- Source power nodes with head background: `rest.plot_power_source`
- Atlas sanity check: `rest.plot_atlasregions`

Look for:

- abnormal PSD shapes (e.g., huge low-frequency drift, strong line noise harmonics)
- very sparse or NaN connectivity matrices (often a sign of too few epochs or failure in virtual channel extraction)
- inconsistent ROI counts across subjects (often from missing channels or source points being outside the brain)

### 5.9 Export and group-level analysis

Use:

- `rest.features2csv` (serial)
- `rest.features2csv_parallel` (parallel)

Then analyze in:

- MATLAB tables
- Python/pandas
- R/tidyverse

Because graph/nodal features create many columns, you may prefer:

- exporting only global measures for certain analyses
- reducing dimensionality (PCA) on nodal metrics
- predefining a small ROI subset

---

## 6) Common Pitfalls and Fixes

### "No overlapping channel labels between data and elec template"

Cause:

- Your EEG channel labels do not match the template file labels.

Fix:

- Provide a matching `TemplateElecFile` for your cap, or
- Provide a FieldTrip `Elec` struct via `Elec`, or
- Ensure `EEG.chanlocs` contains valid XYZ and labels.

### "FieldTrip not found on path"

Fix:

- Add FieldTrip root (not genpath) and call `ft_defaults`, or
- Set `AutoAddDeps=true` and provide `FieldTripRoot`.

### Parcellation/network labels look wrong

Cause:

- `AtlasPath` metadata does not align with your node ordering.

Fix:

- Prefer using `AtlasPath` *without* `SourcePos` (let the atlas define the grid), or
- If you provide `SourcePos` subset, also provide an `AtlasPath` that corresponds to that same subset ordering.

### Source plots have no background

Fix:

- Provide `SurfaceModelPath` (e.g., FieldTrip template `template/anatomy/surface_white_both.mat`), or
- Ensure `HeadModelPath` is set; `rest.plot_power_source` can draw a light scalp mesh as fallback.

---

## 7) Pointers to Real Examples in This Repo

- End-to-end resting-state test:
  - `test/rest_end_to_end.m`
- Atlas centroid CSV (Schaefer2018 100 parcels, 7 networks):
  - `resources/atlas/Schaefer2018_100Parcels_7Networks_order_FSLMNI152_1mm.Centroid_RAS.csv`
