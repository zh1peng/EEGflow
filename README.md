# EEGflow

EEGflow is a MATLAB toolbox for EEG preprocessing and analysis built on a **state + pipeline** design.
Prep and analysis are decoupled so you can compose workflows from small, testable steps.

This README focuses on **preprocessing**. It is written to be friendly to humans and LLMs.

----------------------------------------------------------------------
## Prep design logic (quick mental model)

- **State is the payload**: every step is `state = prep.<op>(state, args, meta)`.
- **Steps are middleware**: each op reads/writes `state` and appends history.
- **Registry maps op -> function**: the pipeline resolves `op` names using a registry.
- **Job JSON is the spec**: list of steps with `op` and `args`.
- **setup_io fills I/O + logging**: it injects `filename/filepath`, `LogFile`, `LogPath`.

----------------------------------------------------------------------
## Prep steps available

Current prep ops (from `+prep`):

- I/O: `load_set`, `load_mff`, `save_set`
- Basic: `downsample`, `filter`, `remove_powerline`
- Segment: `crop_by_markers`, `segment_task`, `segment_rest`
- Clean: `remove_bad_channels`, `remove_bad_epoch`, `remove_bad_ICs`
- Channel ops: `remove_channels`, `select_channels`, `interpolate`, `interpolate_bad_channels_epoch`
- Misc: `reref`, `correct_baseline`, `edit_chantype`, `insert_relative_markers`

See each function header for full parameter docs.

----------------------------------------------------------------------
## Job JSON (LLM-friendly schema)

Top level:

- `steps` (required): array of step objects
- `Options` (optional): e.g., `{ "validate_only": false }`

Each step object:

- `id`   string
- `name` string
- `op`   string (must match a prep op name)
- `args` object (parameters; can be empty)

Minimal example (no housekeeping fields):

```json
{
  "steps": [
    { "id":"S001", "name":"Load", "op":"load_set",
      "args": { "filename":"", "filepath":"" } },
    { "id":"S002", "name":"Filter", "op":"filter",
      "args": { "LowCutoff":0.5, "HighCutoff":30 } },
    { "id":"S003", "name":"BadChannels", "op":"remove_bad_channels",
      "args": { "Action":"remove" } },
    { "id":"S004", "name":"Save", "op":"save_set",
      "args": { "filename":"", "filepath":"" } }
  ],
  "Options": { "validate_only": false }
}
```

### What setup_io injects

`prep.setup_io` automatically populates:

- `filename`, `filepath` for `load_set/load_mff` and `save_set`
- `LogFile` for most steps
- `LogPath` for ops that write plots/files:
  - `remove_bad_channels`
  - `remove_bad_ICs`

You can omit these fields in the JSON.

----------------------------------------------------------------------
## End-to-end prep usage (script style)

This is the same flow as `test/prep_end_to_end.m`, but simplified.

```matlab
% Paths
repoRoot   = getenv('EEGFLOW_ROOT');
dataDir    = fullfile(repoRoot, 'test', 'data', 'raw');
outDir     = fullfile(repoRoot, 'test', 'out', 'prep_run');
configPath = fullfile(repoRoot, 'config_template', 'prep_config.json');

% Load job
cfg = flow.load_cfg(configPath);

% Pick input file by regex (adjust pattern to your dataset)
[paths, names] = filesearch_regexp(dataDir, '^sub-.*\\.set$', 1);
if isempty(names), error('No .set files found.'); end

% Populate IO + logging fields
cfg = prep.setup_io(cfg, ...
    'InputPath', paths{1}, ...
    'InputFilename', names{1}, ...
    'OutputPath', outDir, ...
    'Suffix', '_cleaned');

% Build pipeline (prep registry is used by default)
[pipe, state, cfg] = prep.build_pipeline(cfg);

% Run
[state_out, report] = pipe.run('stop_on_error', true);
```

Tip: use `pipe.validate()` to check arguments without running heavy ops.

----------------------------------------------------------------------
## Advanced: add your own prep step

1) Write a step:

```matlab
function state = my_step(state, args, meta)
state = log_step(state, meta, args.LogFile, '[my_step] running...');
% ... do work ...
state = state_update_history(state, 'my_step', args, 'success', struct());
end
```

2) Register it:

```matlab
reg = prep.register_new_op('my_step', @my_step);
[pipe, state, cfg] = prep.build_pipeline(cfg, 'Registry', reg);
```

3) Add it to JSON:

```json
{ "id":"S999", "name":"MyStep", "op":"my_step", "args": {} }
```

Notes:
- If your custom step needs `LogFile`, either add it in `args` or extend `setup_io` to inject it.
- `register_new_op` errors on duplicates unless `AllowOverride = true`.

----------------------------------------------------------------------
## Advanced: add your own analysis step

```matlab
function state = my_analysis_step(state, args, meta)
state = state_update_history(state, 'my_analysis_step', args, 'success', struct());
end

reg = analysis.register_new_op('my_analysis_step', @my_analysis_step);
```

----------------------------------------------------------------------
## Structure

- `+prep`: preprocessing steps and helpers
- `+analysis`: analysis steps and helpers
- `config_template`: job/config templates
- `utils`: general utilities
