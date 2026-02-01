---
name: eegflow-prep
description: EEGflow preprocessing workflows in MATLAB. Use when working with +prep steps, prep job JSON files, prep.setup_io, prep.build_pipeline, or when troubleshooting preprocessing pipelines and step arguments. Also use when adding custom prep steps via prep.register_new_op.
---

# EEGflow Prep Skill

Use this skill to build, run, and debug EEGflow preprocessing pipelines.

## Quick workflow (default)

1) Load job JSON:
   - `cfg = flow.load_cfg(configPath);`
2) Pick input file:
   - use `filesearch_regexp` to locate `.set` files in the raw data folder.
3) Populate IO/logging:
   - `cfg = prep.setup_io(cfg, 'InputPath', ..., 'InputFilename', ..., 'OutputPath', ...);`
4) Build pipeline:
   - `[pipe, state, cfg] = prep.build_pipeline(cfg);`
5) Run or validate:
   - `pipe.run('stop_on_error', true);`
   - `pipe.validate();`

## Key conventions

- **State** is the payload: each step is `state = prep.<op>(state, args, meta)`.
- **Job JSON** lists steps and args. Keep housekeeping fields out of JSON.
- **setup_io** injects `filename/filepath`, `LogFile`, and `LogPath` automatically.
- **Registry** is prep-only by default (from `+prep/private/init_registry.m`).

## When to load references

- **Need exact step arguments or defaults** -> read `references/prep_ops.md`
- **Need JSON schema details or examples** -> read `references/job_json.md`

## Custom prep steps

To add a new op:

1) Write a step function: `state = my_step(state, args, meta)`
2) Register it:
   - `reg = prep.register_new_op('my_step', @my_step);`
3) Build pipeline with custom registry:
   - `[pipe, state, cfg] = prep.build_pipeline(cfg, 'Registry', reg);`

`register_new_op` rejects duplicates unless `AllowOverride = true`.
