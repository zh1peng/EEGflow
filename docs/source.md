# Generic Source-Space Analysis

EEGflow source analysis has one shared reconstruction layer:

```text
source: sensor epochs -> source/parcel virtual channels
+analysis: ERP/TF condition logic and features
+rest: resting power/connectivity/graph features
```

The canonical source data struct is:

```matlab
src.label
src.trial        % src.trial{t} = [nSourceOrParcel x nTime]
src.time
src.fsample
src.level        % 'source' or 'parcel'
src.atlas
src.parcellation
src.source_pos
src.unit
src.cfg
```

## Core Workflow

```matlab
state = source.check_headmodel(state, args);
state = source.reconstruct_epochs(state, args);
state = source.parcellate_timeseries(state, args);
```

Geometry QC is stored in `state.source.geometry.*` and summarized in
`state.source.qc.geometry`. Source signal QC and parcel coverage are written to
`state.source.qc.signal` and `state.source.qc.parcellation`.

Use template names instead of hard-coded paths when possible:

```matlab
'HeadModelTemplate', 'fieldtrip_standard_bem'
'ElectrodeTemplate', 'fieldtrip_standard_1005'
'AtlasTemplate', 'Schaefer100'
```

## Downstream Modules

ERP source workflows should call analysis-layer functions:

```matlab
state = analysis.erp_compute_source_erps(state, args);
state = analysis.erp_compute_source_contrast(state, args);
state = analysis.erp_extract_source_feature(state, args);
```

TF source workflows should call:

```matlab
state = analysis.tf_compute_source(state, args);
state = analysis.tf_extract_source_feature(state, args);
```

Resting-state workflows keep power/connectivity/graph logic in `+rest`, but
reuse `+source` for headmodel loading, electrode QC, and LCMV spatial filters.

## Interpretation Boundaries

Source signals are model-derived estimates, not direct measurements. Template
MRI plus standard montage supports coarse source-reconstructed cortical
electrophysiological activity, not precise cortical generators.

Signed source ERP amplitudes depend on source orientation. Parcel averaging can
cancel opposite signs. For generic features, prefer `absolute`, `rms`, `power`,
or parcel `first_pc`; use signed waveforms mainly for display or carefully
defined ERP contrasts. Coarse parcellations such as Schaefer100 are the default
starting point.
