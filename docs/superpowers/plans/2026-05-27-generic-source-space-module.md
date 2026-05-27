# Generic Source-Space Module Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Track implementation with checkbox (`- [x]`) syntax.

**Goal:** Make source-space analysis a generic EEGflow capability shared by resting-state, ERP, and time-frequency workflows. The source layer should output virtual-channel data where source points or parcels replace scalp electrodes:

```text
sensor epochs: trial x electrode x time
source epochs: trial x source/parcel x time
```

This plan intentionally avoids task-specific MID logic and avoids BrainEnrich/export logic. The current scope is generic source-space reconstruction and source-level ERP-like feature extraction.

**Architecture:** Introduce `+source` as the common source-space layer. Keep `+rest` public functions as compatibility wrappers where needed, but make new canonical state fields use `state.source.*`. Downstream modules consume `state.source.epochs` and treat parcels/source points as virtual electrodes.

**Tech Stack:** MATLAB R2025b, EEGLAB, FieldTrip, EEGflow state + pipeline conventions.

---

### File Structure

- Create: `+source/check_headmodel.m`
- Create: `+source/inspect_headmodel.m`
- Create: `+source/eeglab_to_fieldtrip_epoched.m`
- Create: `+source/compute_spatial_filter.m`
- Create: `+source/reconstruct_epochs.m`
- Create: `+source/compute_erps.m`
- Create: `+source/extract_window_feature.m`
- Create: `+source/atlas_load.m`
- Create: `+source/private/load_headmodel.m`
- Create: `+source/private/atlas_table_to_pos.m`
- Modify: `+rest/check_headmodel.m` into a compatibility wrapper.
- Modify: `+rest/inspect_headmodel.m` into a compatibility wrapper.
- Modify: `+rest/compute_all_features.m` to inherit geometry from `state.source.geometry` first, with `state.rest.headmodel` fallback.
- Modify: `+analysis/private/init_registry.m` and `+rest/private/init_registry.m` to expose generic source operations.
- Modify: `config_template/rest_config.json`, add `config_template/source_config.json`, and document `docs/source.md`.

### Task 1: Generic Geometry QC

**Files:**
- `+source/check_headmodel.m`
- `+source/inspect_headmodel.m`
- `+source/private/load_headmodel.m`

- [x] Move headmodel/electrode QC behavior from `rest.check_headmodel` into `source.check_headmodel`.
- [x] Store canonical outputs in `state.source.geometry.headmodel`, `state.source.geometry.elec`, `state.source.geometry.qc`, and `state.source.geometry.unit`.
- [x] Support `RealignMethod='none'|'project'|'headshape'|'template'|'fiducial'|'interactive'`.
- [x] Preserve `PlotQC`, `ReviewRequired`, and QC threshold behavior.

### Task 2: Generic Source Epoch Reconstruction

**Files:**
- `+source/eeglab_to_fieldtrip_epoched.m`
- `+source/compute_spatial_filter.m`
- `+source/reconstruct_epochs.m`
- `+source/atlas_load.m`
- `+source/private/atlas_table_to_pos.m`

- [x] Add a generic EEGLAB-to-FieldTrip converter for epoched data.
- [x] Add a generic LCMV spatial-filter function that defaults to broadband covariance (`FilterData=false`) instead of rest-only bandpass covariance.
- [x] Add `source.reconstruct_epochs` to apply the filter to each trial with `ft_virtualchannel`.
- [x] Store output as `state.source.epochs.trial{t} = [nSourceOrParcel x nTime]`.
- [x] Support `AtlasPath`, `SourcePos`, and `SourceIndex` for parcel/source-point selection.
- [x] Support source signal summaries: `signed`, `absolute`, `rms`/`vectornorm`, and `power`.

### Task 3: Source-Level ERP-Like Operations

**Files:**
- `+source/compute_erps.m`
- `+source/extract_window_feature.m`

- [x] Average source/parcel epochs by condition with optional baseline correction.
- [x] Treat parcels/source points as virtual electrodes in `state.source.erp.conditions.(condition).avg`.
- [x] Extract source/parcel window features with `mean`, `peak_positive`, `peak_negative`, `peak_absolute`, and `rms`.
- [x] Support condition contrasts at the feature level.

### Task 4: Backward Compatibility and Registry Hooks

**Files:**
- `+rest/check_headmodel.m`
- `+rest/inspect_headmodel.m`
- `+rest/private/init_registry.m`
- `+analysis/private/init_registry.m`

- [x] Keep existing `rest.check_headmodel` calls working by delegating to `source.check_headmodel`.
- [x] Mirror `state.source.geometry` into `state.rest.headmodel` for compatibility with existing scripts.
- [x] Keep `rest.inspect_headmodel` as a wrapper around `source.inspect_headmodel`.
- [x] Register `source_reconstruct_epochs`, `source_compute_erps`, and `source_extract_window_feature` in analysis/rest registries.

### Task 5: Rest Orchestrator Integration

**Files:**
- `+rest/compute_all_features.m`

- [x] Prefer `state.source.geometry` when `UseCheckedHeadmodel=true`.
- [x] Fall back to legacy `state.rest.headmodel`.
- [x] Continue to strip large geometry structs from history.
- [x] Preserve existing rest end-to-end behavior.

### Task 6: Documentation and Config

**Files:**
- `docs/source.md`
- `docs/rest.md`
- `config_template/source_config.json`
- `config_template/rest_config.json`

- [x] Document `source.check_headmodel` as the recommended generic API.
- [x] Document source epochs as `trial x source/parcel x time`.
- [x] Document orientation/sign caveats and `SourceSignalMode`.
- [x] Add a generic source config template without MID or BrainEnrich assumptions.
- [x] Mark `rest.check_headmodel` as a compatibility wrapper.

### Task 7: Verification

**Commands:**

- [x] Source smoke test with explicit `SourcePos`: reconstruct 8 source epochs, compute source ERP, extract 0-100 ms feature.
- [x] Source smoke test with `AtlasPath + SourceIndex`: reconstruct 8 parcel epochs, verify labels/parcellation and `SourceSignalMode='power'`.
- [x] `matlab -batch "addpath(genpath(pwd)); ...; run('test/rest_module_improvements_test.m')"`
- [x] `matlab -batch "run('test/rest_end_to_end.m')"`
- [x] Source pipeline smoke test with `source.build_pipeline` and registered source ops.
- [x] `git diff --check`

Expected: all pass. Test/output artifacts remain ignored and untracked.
