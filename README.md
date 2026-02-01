# EEGflow

EEGflow is a MATLAB toolbox for EEG preprocessing and analysis built around a **state + pipeline** design.  
Prep and analysis are decoupled so you can compose workflows from small, testable steps.

## Design logic (prep)

- **State is the payload**: each step receives and returns a `state` struct (with `state.EEG`, `state.cfg`, `state.history`, etc.).
- **Steps are middleware**: each operation is a function `state = prep.<op>(state, args, meta)`.
- **Registry maps op → function**: a registry is used by the pipeline to resolve step names.
- **Job file (JSON) is the spec**: a list of steps with `op` and `args`; minimal placeholders are OK.
- **setup_io fills the blanks**: `prep.setup_io` populates filenames, paths, log files, and per‑step args.

## Prep: available steps

Current prep ops (from `+prep`):

- `load_set`, `load_mff`, `save_set`
- `downsample`, `filter`, `remove_powerline`
- `crop_by_markers`, `segment_task`, `segment_rest`
- `remove_bad_channels`, `remove_bad_epoch`, `remove_bad_ICs`
- `remove_channels`, `select_channels`, `interpolate`, `interpolate_bad_channels_epoch`
- `reref`, `correct_baseline`, `edit_chantype`, `insert_relative_markers`

See each function header for full parameter docs.

## Job JSON: structure and arguments

Each job file has a `steps` array. Each step includes:

- `id`        unique string
- `name`      human‑readable name
- `op`        operation name (matches a prep function)
- `args`      step parameters (can be empty placeholders)

Example (minimal):

```json
{
  "steps": [
    { "id":"S001", "name":"Load", "op":"load_set",
      "args": { "filename":"", "filepath":"", "LogFile":"" } },
    { "id":"S002", "name":"Filter", "op":"filter",
      "args": { "LowCutoff":0.5, "HighCutoff":30, "LogFile":"" } },
    { "id":"S003", "name":"BadChannels", "op":"remove_bad_channels",
      "args": { "Action":"remove", "LogPath":"", "LogFile":"" } },
    { "id":"S004", "name":"Save", "op":"save_set",
      "args": { "filename":"", "filepath":"", "LogFile":"" } }
  ],
  "Options": { "validate_only": false }
}
```

### Common args you’ll see

- **I/O**
  - `filename`, `filepath` for `load_set/load_mff` and `save_set`
- **Logging**
  - `LogFile` (most steps)
  - `LogPath` (only steps that write plots/files: `remove_bad_channels`, `remove_bad_ICs`)

You can leave these blank in the JSON. `prep.setup_io` will populate them based on the input/output paths you pass.

## Building and running a prep pipeline

```matlab
% Paths
repoRoot  = getenv('EEGFLOW_ROOT');
dataDir   = fullfile(repoRoot, 'test', 'data', 'raw');
outDir    = fullfile(repoRoot, 'test', 'out', 'prep_run');
configPath= fullfile(repoRoot, 'config_template', 'prep_config.json');

% Load config and pick input file
cfg = flow.load_cfg(configPath);
[paths, names] = filesearch_regexp(dataDir, '^sub-.*\\.set$', 1);
if isempty(names), error('No .set files found.'); end

% Fill IO fields + per-step args
cfg = prep.setup_io(cfg, ...
    'InputPath', paths{1}, ...
    'InputFilename', names{1}, ...
    'OutputPath', outDir, ...
    'Suffix', '_cleaned');

% Build pipeline (prep-only registry for speed)
reg = flow.Registry('prep');
[pipe, state, cfg] = prep.build_pipeline(cfg, 'Registry', reg, 'ConfigureIO', false);

% Run
[state_out, report] = pipe.run('stop_on_error', true);
```

Tip: use `pipe.validate()` to check arguments without running heavy ops.

## Advanced: plug in your own prep steps

1) Write a step function:

```matlab
function state = my_step(state, args, meta)
% Example custom step
state = log_step(state, meta, args.LogFile, '[my_step] running...');
% ... do work ...
state = state_update_history(state, 'my_step', args, 'success', struct());
end
```

2) Register it:

```matlab
reg = flow.Registry('prep');
reg('my_step') = @my_step;

[pipe, state, cfg] = prep.build_pipeline(cfg, 'Registry', reg, 'ConfigureIO', false);
```

3) Add it to your JSON:

```json
{ "id":"S999", "name":"MyStep", "op":"my_step", "args": { "LogFile":"" } }
```

Your step will then behave like a first‑class prep op.

## Structure

- `+prep`: preprocessing steps and helpers
- `+analysis`: analysis steps and helpers
- `config_template`: job/config templates
- `utils`: general utilities
