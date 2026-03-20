# Changelog

## v0.6.0 - 2026-03-20

- Removed the redundant `analysis.plot_erp` alias and made `analysis.erp_plot_erp` the single canonical GA ERP plotting entry point.
- Bumped analysis module version to `0.6.0`.
- Clarified ERP waveform stats semantics in `docs/erp.md`:
  - waveform stats default to the full ERP epoch,
  - `time_window` in `erp_compute_stats` / `erp_compute_subject_contrast_stats` is an explicit override,
  - plot-time `time_window` is display-only for waveform figures.

## v0.5.0 - 2026-03-17

- Added `analysis.Dataset.merge(new_cond_name, conds_to_merge)` for strict trial-level condition merging without overwriting source conditions.
- Added strict metadata synchronization in Dataset merge for `meta.conditions`, `meta.trialN`, `meta.summary`, and `meta.derived_conditions`.
- Added subject-level ERP difference-wave workflow (within-group only):
  - `analysis.erp_compute_subject_contrast`
  - `analysis.erp_compute_subject_contrast_stats`
  - `analysis.erp_plot_subject_contrast`
  - `analysis.erp_extract_subject_contrast_feature`
- Added `state.Results.SubjectContrasts` as a dedicated storage branch for subject-level difference waves and their stats/features.
- Registered all new subject-contrast ERP ops in analysis registry for pipeline compatibility.
- Updated ERP guide (`docs/erp.md`) with Dataset merge usage and full subject-contrast analysis flow.
- Bumped analysis module version to `0.5.0`.

## v0.4.0 - 2026-03-17

- Added `analysis.get_version()` and surfaced version info (`v0.4.0`) in ERP compute logs and ERP figure titles for easier run/result traceability.
- Unified ERP polarity display in line plots: both GA ERP and contrast ERP now use EEG convention (negative up, positive down).
- Improved contrast plotting readability and safety:
  - legend now uses `Group:Condition` labels,
  - significance shading uses robust patch rectangles,
  - plotting now validates ROI/time-window compatibility with computed stats.
- Improved selection usability:
  - `define_group` now normalizes subject IDs (with/without `sub_`),
  - `select_conditions` is now case-insensitive and preserves user-provided order,
  - channel validation for ROI/targets is now case-insensitive.
- Added stricter and earlier validation:
  - time windows must overlap dataset time axis,
  - clearer required-argument checks for ERP contrast and selection helpers,
  - `show_error` now accepts `sd` as alias of `std` and errors on unsupported values.
- Improved ERP stats behavior:
  - added argument validation for `mcc` and `time_window`,
  - added minimum-subject guard for paired tests,
  - fixed ROI stats shape handling to keep time vectors aligned,
  - renamed reported outputs to "significant segments" (and kept `sig_clusters` as backward-compatible alias).
- Improved feature extraction robustness:
  - validates window overlap,
  - enforces consistent feature output length across rows,
  - sanitizes dynamic feature field names.
- Improved extraction metadata and diagnostics:
  - condition list now preserves marker/alias order (`stable`),
  - fixed extraction warning count formatting,
  - stores warnings in `Out.meta.warnings`,
  - aligns dataset summary compatibility via `trialN` and `summary`,
  - stores extractor toolbox version in `Out.meta.toolbox_version`.
- Updated ERP documentation (`docs/erp.md`) to reflect the new behavior and versioned usage notes.

## 2026-03-05

- `analysis.extract_epoch` now supports aliasing multiple markers to the same condition by concatenating trials along the 3rd dimension instead of overwriting previous data.
- Added a guard to preserve existing merged condition data when one marker extraction fails, and added a clear size-mismatch error when merge dimensions are incompatible.
- Updated trial-count summary generation to aggregate counts by subject/condition before pivoting, so many-to-one alias mappings are reported correctly.
- Updated docs in `docs/erp.md` and function header docs in `+analysis/extract_epoch.m` to document many-to-one alias behavior.
