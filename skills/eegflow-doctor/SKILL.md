---
name: eegflow-doctor
description: EEGflow environment diagnostics and setup. Use when MATLAB, EEGLAB, FASTER, ICLabel, or CleanLine are missing from path, or when preprocessing/analysis steps fail due to missing dependencies or path issues. Provides a checklist and commands to verify/add paths and environment variables.
---

# EEGflow Doctor Skill

Use this skill to diagnose and fix environment/path issues for EEGflow.

## Quick workflow

1) Identify missing dependency from the error message (e.g., `pop_loadset` not found).
2) Run the checklist in `references/doctor_checks.md`.
3) Ask the user for missing root paths if needed (EEGLAB, FASTER, ICLabel, CleanLine).
4) Add paths in MATLAB (`addpath(genpath(...))`), then `savepath` if desired.
5) Re-run the failing step.

## Key checks (summary)

- MATLAB is available and running the intended version.
- `EEGFLOW_ROOT` is set and on MATLAB path.
- EEGLAB is on path (`which pop_loadset -all`).
- FASTER functions are on path (e.g., `which FASTER_rejchan -all`).
- ICLabel is on path (e.g., `which iclabel -all`).
- CleanLine is on path (if `remove_powerline` uses it).

## When to load references

- For a full checklist and exact MATLAB commands -> open `references/doctor_checks.md`.

## Script

- `scripts/doctor_check.m` runs automated checks and optionally adds paths.

## Constraints

- Do not modify EEGflow code when troubleshooting environment issues.
- Prefer adding paths or setting environment variables over code changes.
