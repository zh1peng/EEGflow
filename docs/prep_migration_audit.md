# Prep migration audit — 2026-11-05

Reference: the current sibling `EEGdojo/+prep` and its `utils` directory.
Scope: all 20 preprocessing operations, their parameter declarations, early
returns, output fields, and local calculation/plotting helpers. `prep.Pipeline`
is replaced by EEGflow's `flow.Pipeline`; it is not an algorithm to copy.

## Contract

- Keep EEGdojo's calculation order, thresholds, defaults and input validators.
- Adapt `EEG` to `state.EEG`, Name–Value inputs to `args`/`state.cfg`, and `out`
  to `state.history(end).metrics`. Preserve `out` even when a step is skipped.
- Keep log routing, pipeline validation and registry code outside the algorithm.
- Convert JSON types/shapes at the configuration boundary, rather than widening
  individual algorithms' accepted inputs.
- Do not silently fix reference-code issues or change algorithms during migration.

## Reviewed operations

| Operations | Algorithm checks |
| --- | --- |
| `load_set`, `load_mff`, `save_set` | Same EEGLAB calls and file arguments |
| `filter`, `downsample`, `remove_powerline` | Filter order, resampling rate, harmonics, notch edges and CleanLine arguments |
| `crop_by_markers`, `insert_relative_markers` | Event selection, rounding, bounds, overwrite mask, sorting and time metadata |
| `select_channels`, `remove_channels`, `edit_chantype`, `reref` | Label/index selection, excluded channels and reference calculation |
| `remove_bad_channels` | Detector switches, thresholds, combination order, removal/flagging and original locations |
| `remove_bad_ICs` | Rank/PCA, ICA recomputation, weight transfer, ICLabel, brain protection, FASTER, multichannel ECG and plots |
| `remove_bad_epoch`, `interpolate_bad_channels_epoch` | Detection, original trial IDs, epoch-specific channel indices and interpolation |
| `interpolate`, `correct_baseline` | Interpolation target locations, baseline window and skipped outputs |
| `segment_task`, `segment_rest` | Epoch construction/counts, 4000 ms rest default, empty results and preserved ICA |

The 110 parameter declarations (defaults and validators) match the reference.
Calculation and plotting helpers match after ignoring comments/formatting:
`FASTER_rejchan`, `cleanraw_rejchan`, `getrank`, `batch_saveas`,
`draw_selectcomps`, `logplot_badchannels`, `logreport_badchannels`,
`chans2idx`, and `idx2chans`. Logging helpers retain EEGflow routing.

## Changes from the second audit

- Restored `KnownBadLabel` default `[]` and the reference numeric/empty validator.
- Restored the original validators and input handling for channel selection,
  channel removal and rereferencing.
- Restored skipped-output fields for baseline correction, filtering,
  interpolation and task segmentation.
- Restored `draw_selectcomps` text settings.
- `setup_io` no longer converts `KnownBadLabel` to cellstr. It normalizes actual
  label fields and JSON channel-index vectors before the algorithms run.

## Explicit retained correction

Before ECG correlation, `remove_bad_ICs` obtains activations with
`EEG.icaact = eeg_getica(EEG)`. This retains the previously requested API fix and
supports EEGLAB with activation caching disabled. It is one executable
difference from EEGdojo, not a change to correlation, thresholds or rejection
rules. The extra call is intentionally recorded rather than described as an
exact source match.

## Verification and limits

`test/prep_migration_defaults_test.m` compares all parameter declarations and
MATLAB-resolved defaults directly against the sibling EEGdojo checkout. It
requires that checkout; it does not substitute for data-level verification.

Targeted synthetic-data comparisons use the installed MATLAB R2025b and EEGLAB
2023.1. The first audit covered ICA with/without high-pass filtering, activation
caching disabled, IC flag dimensions/endpoints, marker replacement, channel
selection, rest segmentation and interpolation. The second audit checks
filtering, downsampling, rereferencing, channel typing/removal/selection,
baseline correction, skipped outputs and JSON parameter conversion.

This is source parity plus targeted regression, not validation of every detector
on real subjects. MFF import, full ICLabel/FASTER rejection and diagnostic image
generation have not been rerun end to end.

Reference/environment issues are not silently repaired here:

- EEGdojo's `KnownBadLabel` documentation describes labels, but its parser
  accepts numeric/empty input. That inconsistency is preserved and must be
  resolved explicitly in a separate change.
- The installed EEGLAB `eegrej` uses `iRegion1+1:size(regions)` and errors on
  MATLAB R2025b when the affected crop branch is reached. Both toolboxes are
  affected. Rest comparisons used a full-length block to avoid that branch;
  the external dependency was not modified.

Follow-up (2026-11-05): at the user's explicit request, the installed EEGLAB
`eegrej.m:139` was changed to `iRegion1+1:size(regions,1)`. The movie regression
now checks actual interior cropping, shifted events and the full six-step
movie pipeline; these pass. The rest comparisons above describe the earlier
audit and have not been rerun as part of this movie-specific verification.
