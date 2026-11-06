# Movie analysis

`+movie` collects continuous segments across subjects and supports QC, CorrCA,
ISC, RSA, stimulus-feature resampling and CP tensor decomposition. It does not
replace preprocessing: `prep.segment_task` and `prep.segment_rest` make epochs,
while `movie.collect_segments` calls `prep.crop_by_markers` for each input file
and assembles a study dataset.

TRF and historical backup functions are not included. There are no aliases for
the EEGdojo function names that were renamed.

## Setup and dependencies

Add the EEGflow root and `utils` to the MATLAB path, and initialize EEGLAB.
The original EEGdojo module is not required or added to the path.

```matlab
addpath(eegflowRoot, fullfile(eegflowRoot, 'utils'));
addpath(eeglabRoot);
eeglab nogui;
```

- QC requires EEGLAB's FIR filter and `clean_rawdata` plugin.
- Signal Processing and Statistics and Machine Learning Toolbox functions are
  used by the signal processing, similarity, statistics and visualization paths.
- Parallel Computing Toolbox is optional for the existing parallel branches.
- CorrCA and its regularized inverse, and natural sorting, are bundled in
  `+movie/private`; original author comments are retained.
- `run_cp` requires Tensor Toolbox (`tensor`, `cp_als`) on the path.
- Optional CSD processing requires the external CSD Toolbox (`CSD`, `GetGH`).

## Collect segments and apply QC

```matlab
data = movie.collect_segments( ...
    'study_path', setDirectory, ...
    'subject_parser', '(?<sub>sub-[^_]+)', ...
    'StartMarker', 'video_start', 'EndMarker', 'video_stop', ...
    'check_quality', true);

% Example study-specific threshold, not a universal quality criterion.
selected = movie.qc_filter(data, ...
    'metrics_to_analyze', {'percent_retained_by_windows'}, ...
    'thresholds', struct('percent_retained_by_windows', 85), ...
    'filter_data', true);
```

Each `data.sub_*.data` is channels by time (or channels by frequency by time
when `tfr=true`). `data.meta` contains sampling rate, channel locations and
collection settings. The subject parser must produce distinct subject keys;
CorrCA's study wrapper selects fields beginning with `sub_`.

`collect_segments` retains the original processing order:

1. Load a file and select channels.
2. If `check_quality=true`, calculate QC on a temporary **1 Hz high-pass copy
   of the input recording, before cropping**. The default is `false`.
3. Apply the analysis `locutoff`/`hicutoff` to the original working EEG if set.
4. Crop between markers using `prep.crop_by_markers`.
5. Optionally interpolate to `expected_length` or `movie_duration_sec` using
   the original PCHIP method.
6. Apply optional CSD and then Hilbert envelope to the cropped/interpolated
   arrays, then assemble each subject's analysis data.

QC is stored in `data.sub_*.quality_info` and `data.meta.data_quality`. It
describes the pre-crop input, not necessarily the extracted video. If a file
contains an entire session, this is session-level QC. No bad-window mask is
applied to the analysis data. Analysis filtering is independent of QC filtering.

`qc_filter` reads the existing table; it does not filter EEG or recompute metrics.
It writes `meta.auto_qc`, plots pass/fail bars, and defaults to removing failed
**subject fields from the returned dataset**. It does not alter `.set` files.
`filter_data=false` preserves all subject data. The original QC table is kept;
`meta.data_quality_after_qc` contains only retained rows when filtering is on.
NaN values pass, as in the original implementation. Unspecified thresholds use
median +/- 3 MAD by default, with the original per-metric direction rules.

For QC of files without collecting segments:

```matlab
[metrics, flags] = movie.qc_files('study_path', setDirectory, ...
    'parallel', false, ...
    'metrics_to_analyze', {'percent_retained_by_windows'});
keptFiles = cellstr(metrics.file(flags.include_auto));
data = movie.collect_segments('setFile', keptFiles, ...
    'StartMarker', 'video_start', 'EndMarker', 'video_stop');
```

`qc_files` evaluates each complete `.set` and defaults to `qc_locutoff=1`.
Set it to `[]` or `0` to disable the QC high-pass. `qc_lengths(counts, fs,
tolerance_sec)` returns length-based flags/indices relative to the median
sample count; it does not remove data or resample it. Its default tolerance is
1 second. In the pipeline, lengths describe the segment after any requested
interpolation. For TFR data, each subject's `tfr_input_samples` records how
many EEG samples entered the transform. Length QC uses that count at `meta.fs`.

## Optional high-pass inside calculate_data_quality

```matlab
quality = calculate_data_quality(EEG, 'qc_locutoff', 1);
```

The new `qc_locutoff` option defaults to `[]` (off); `0` also disables it.
When enabled, it filters a local copy before all signal-based metrics, not
only `clean_windows`. The caller's EEG is unchanged. Metadata-based bad-channel
and rejected-epoch percentages retain their original definitions.

`qc_files` and `collect_segments` already filter their QC copies and leave this
new option at its disabled default, so these entry points do not filter twice.
The clean-window defaults remain 20% bad channels, RMS tolerance `[-3.5, 5]`,
1-second windows and 66% overlap.

## CorrCA, ISC and RSA

```matlab
[W, componentISC, Y, A] = movie.run_corrca(selected, 'shrinkage', 0.1);
% Y: time x components x subjects. Select one component explicitly for ISC.
signals = reshape(Y(:,1,:), size(Y,1), size(Y,3));
[isc, info, pairs] = movie.compute_isc(signals, 'pairwise', true);
inference = movie.test_isc(signals, 'nPerm', 1000, ...
    'randomSeed', 42, 'parallel', false);
movie.plot_isc_test(inference);

% Behavior rows MUST match the subject order in Y/pairs.
behaviorSimilarity = movie.build_similarity_univariate(behaviorScores);
stats = movie.rsa_mantel(pairs, behaviorSimilarity, 'seed', 42);
```

`compute_isc` accepts time by subjects, not the full 3-D CorrCA projection.
`pairwise=true` requests the pair matrix; `fisherZ=true` is the original default
for this matrix. Time-resolved pairwise results also require `overlap`.

`run_corrca_stream` reads `.set` files without stacking all input EEG in memory.
It retains its own original covariance solver and preprocessing. Specify a
common `expected_length` or use equal-length inputs: its original scan chooses
the first file's length, rather than the minimum across all files. The stacked
wrapper trims to the shortest accepted subject and skips empty/channel-mismatched
subjects. Keep subject/behavior ordering aligned after any such exclusions.

## Pipeline interface

```matlab
cfg = flow.load_cfg(fullfile(eegflowRoot, 'config_template', 'movie_config.json'));
cfg.steps(1).args.study_path = setDirectory;
[pipe, state] = movie.build_pipeline(cfg);
[state, report] = pipe.run();
```

Edit the marker names, subject parser and QC threshold in the example for your
study. If segments have already been independently quality-controlled, omit the
QC steps. Numerical and plotting functions also retain direct MATLAB interfaces;
the pipeline uses thin `state, args, meta` adapters, not duplicate algorithms.

| Pipeline operation | Reads / writes |
| --- | --- |
| `collect_segments` | Writes `state.movie.data` |
| `qc_files` | Writes `state.movie.qc.files.metrics` and `.flags` |
| `qc_filter` | Updates `state.movie.data` |
| `qc_lengths` | Reads dataset lengths; writes `state.movie.qc.lengths`; does not filter |
| `run_corrca` | Reads dataset; writes `state.movie.corrca.W/ISC/Y/A`, plus `.p` when `fixed` is supplied |
| `run_corrca_stream` | Reads file arguments; writes `state.movie.corrca.W/ISC/Y/A` |
| `compute_isc` | Reads a CorrCA `component` (default 1); writes `.isc.values/meta/pairwise/component` |
| `test_isc` | Reads a CorrCA `component` (default 1); writes `.isc_test` |
| `plot_isc_test` | Plots `.isc_test` |
| `run_cp` | Reads dataset; writes `.cp` |
| `plot_cp` | Plots `.cp` |

Other array-based functions are called directly, including RSA and feature
resampling. `flow.Pipeline` records execution in `state.runtime.steps`. Movie
pipeline validation checks operation wiring only; it does not run the numerical
functions or load files to validate their arguments.

## Name mapping

| EEGdojo | EEGflow |
| --- | --- |
| `extract_segment` | `collect_segments` |
| `qc_study` | `qc_files` |
| `qc_extract` | `qc_filter` |
| `length_filter` | `qc_lengths` |
| `run_corrca`, `run_corrca_stream` | Unchanged |
| `isc_per_subject` | `compute_isc` |
| `isc_test` | `test_isc` |
| `isc_test_plot` | `plot_isc_test` |
| `plot_ISCtr` | `plot_isc_timecourse` |
| `plot_ISC_band_summary` | `plot_isc_band_summary` |
| `plot_ISC_topo_across_bands` | `plot_isc_topographies` |
| `build_similarity_single` | `build_similarity_univariate` |
| `build_similarity_mutiple` | `build_similarity_multivariate` |
| `rsa_mrqap_summary` | `summarize_rsa_mrqap` |
| `resample_csv_feature` | `resample_features_csv` |
| `resample_one_feature` | `resample_feature` |
| `reorder_similarity`, `rsa_mantel`, `rsa_mrqap` | Unchanged |
| `plot_similarity`, `plot_similarity_embedding` | Unchanged |
| `run_cp`, `plot_cp` | Unchanged |

## Migration scope and retained behavior

The migration changes names, package references and the crop API adapter. The
only new calculation option is the opt-in QC high-pass above. Defaults and
statistical definitions are retained, with these explicitly requested fixes:

- The fixed-projection CorrCA pipeline exposes the existing fifth output as
  `state.movie.corrca.p`; the underlying p-value calculation is unchanged.
- `qc_filter` now treats `amplitude_spread_1k`, `amplitude_spread_global` and
  `global_field_power_mean` as higher-is-worse, matching `qc_files`, for both
  explicit thresholds and MAD cutoffs. Metric formulas and NaN handling are unchanged.
- Optional CSD/Hilbert processing in `collect_segments` now transforms the
  returned cropped/interpolated arrays rather than the discarded pre-crop variable.
- CP sign normalization flips spatial and temporal factors together, preserving
  reconstruction while making temporal peaks positive. `out.cp.U` is synchronized
  with `out.A/B/C`; reconstruction still requires the weights in `out.cp.lambda`.

`qc_lengths`' original report text describes a subsequent resampling step, but
the function itself only calculates flags and indices.

`test/movie_module_test.m` checks QC filtering equivalence/input preservation,
collection and QC scope, subject selection, stacked/streaming CorrCA, ISC,
pipeline execution, similarity/RSA, feature alignment and (when installed) CP
reconstruction on synthetic data. Tests do not require the EEGdojo module.

Verification on MATLAB R2025b, EEGLAB 2023.1 and Tensor Toolbox 3.6 passed the
numerical checks, all six steps in the JSON example, and the migrated plot
entry points. The fixtures now retain samples 129 through 8064 of an 8192-point
recording, removing 128 samples at each end. Tests check exact retained data,
event removal and shifted latencies, pre-crop QC scope, length interpolation,
stacked/streaming CorrCA equivalence and the six-step JSON pipeline on these
interior segments. A direct `eegrej` regression also checks two removed internal
spans, boundary positions and retained event latencies.

The installed EEGLAB 2023.1 dependency was patched at the user's request on
2026-11-05: in `Z:/matlab_toolbox/eeglab2023.1/functions/sigprocfunc/eegrej.m:139`,
`iRegion1+1:size(regions)` became `iRegion1+1:size(regions,1)`. The loop must
iterate over region rows; the original upper bound was a two-element size
vector and raised "Colon operands must be real scalars". The regression
reproduced the error before this one-line change and passed afterward.
This is a local EEGLAB installation fix, not an EEGflow replacement function.
The correction regressions also check fixed-projection pipeline p-values,
upper-bound QC rules, CSD/Hilbert on interior segments (including interpolation),
and CP reconstruction with a deliberately negative temporal peak.

On 2026-11-06, the source audit covered all 24 migrated movie functions and
their parameter defaults. The bundled `corrca`, `regInv` and `natsort` sources
also matched EEGdojo. Separate MATLAB R2025b sessions ran each repository on
the same four synthetic recordings. The 37 compared outputs matched exactly,
including cropped samples, QC, interpolation, TFR power and axes, stacked and
streaming CorrCA, fixed-projection p-values, static and windowed ISC, seeded
permutation statistics, similarity matrices and resampled features. The
comparison excluded creation timestamps and timestamp-based run tags and
checked EEGflow's additional TFR sample count separately. Parallel execution
was outside this comparison.

When interpolation changes a single-channel segment's length before TFR,
`newtimef` in both repositories raises
`Length of data vector must be divisible by frames.`
