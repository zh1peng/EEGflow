# Changelog

## 2026-03-05

- `analysis.extract_epoch` now supports aliasing multiple markers to the same condition by concatenating trials along the 3rd dimension instead of overwriting previous data.
- Added a guard to preserve existing merged condition data when one marker extraction fails, and added a clear size-mismatch error when merge dimensions are incompatible.
- Updated trial-count summary generation to aggregate counts by subject/condition before pivoting, so many-to-one alias mappings are reported correctly.
- Updated docs in `docs/erp.md` and function header docs in `+analysis/extract_epoch.m` to document many-to-one alias behavior.
