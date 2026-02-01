# EEGflow

EEGflow is a MATLAB toolbox for EEG preprocessing and analysis built on a state + pipeline design.
Prep and analysis are decoupled so you can compose workflows from small, testable steps.

This README focuses on preprocessing. It is written to be friendly to humans and LLMs.

----------------------------------------------------------------------
## Prep design logic (quick mental model)

- State is the payload: every step is `state = prep.<op>(state, args, meta)`.
- Steps are middleware: each op reads/writes `state` and appends history.
- Registry maps op -> function: the pipeline resolves step names using a registry.
- Job JSON is the spec: list of steps with `op` and `args`.
- setup_io fills I/O and logging: it injects filename/filepath, LogFile, LogPath.

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

Minimal example:

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

What setup_io injects (you can omit these in JSON):
- filename/filepath for `load_set/load_mff` and `save_set`
- LogFile for most steps
- LogPath for ops that write plots/files: `remove_bad_channels`, `remove_bad_ICs`

----------------------------------------------------------------------
## Prep ops reference (purpose + args)

Notes:
- Defaults shown are the code defaults (from each step's inputParser).
- LogFile/LogPath are auto-injected by `prep.setup_io`.

### I/O
- load_set: load EEGLAB .set
  - args: filename (char, default ''), filepath (char, default ''), LogFile (auto)
- load_mff: load EGI .mff
  - args: filename (char, default ''), filepath (char, default ''), LogFile (auto)
- save_set: save EEGLAB .set
  - args: filename (char, default ''), filepath (char, default ''), LogFile (auto)

### Basic signal ops
- downsample: resample data
  - args: Rate (numeric, default 250), LogFile (auto)
- filter: bandpass or high/low pass
  - args: LowCutoff (numeric, default -1), HighCutoff (numeric, default -1), LogFile (auto)
- remove_powerline: remove line noise
  - args: Method ('cleanline'|'notch', default 'cleanline'), Freq (50), BW (2), NHarm (3), LogFile (auto)

### Segmentation
- crop_by_markers: keep data between start/end markers
  - args: StartMarker (char, default ''), EndMarker (char, default ''), PadSec (0), LogFile (auto)
- segment_task: epoch around markers
  - args: Markers (cellstr, default {}), TimeWindow (ms, [start end], default []), LogFile (auto)
- segment_rest: build rest blocks and fixed-length epochs
  - args: BlockLabel ("EC"), StartCode (10), EndCode ([]), BlockDurSec ([]),
          TrimStartSec (0), TrimEndSec (0), EpochLength (2000 ms),
          EpochOverlap (0.5), LogFile (auto)

### Cleaning: bad channels and epochs
- remove_bad_channels: detect bad channels (multiple detectors)
  - args:
    - ExcludeLabel ({})
    - Action ('remove'|'flag', default 'remove')
    - KnownBadLabel ({})
    - Kurtosis (false), Kurt_Threshold (5)
    - Probability (false), Prob_Threshold (5)
    - Spectrum (false), Spec_Threshold (5), Spec_FreqRange ([1 50])
    - NormOn ('on')
    - FASTER_MeanCorr (false), FASTER_Threshold (0.4), FASTER_RefChan ([]), FASTER_Bandpass ([])
    - FASTER_Variance (false), FASTER_VarThreshold (3)
    - FASTER_Hurst (false), FASTER_HurstThreshold (3)
    - CleanRaw_Flatline (false), Flatline_Sec (5)
    - CleanDrift_Band ([0.25 0.75]), CleanRaw_Noise (false)
    - CleanChan_Corr (0.8), CleanChan_Line (4), CleanChan_MaxBad (0.5), CleanChan_NSamp (50)
    - LogFile (auto), LogPath (auto)
- remove_bad_epoch: detect bad epochs
  - args: Autorej (true), Autorej_MaxRej (2), FASTER (true), LogFile (auto)
- remove_bad_ICs: ICA-based component rejection
  - args:
    - RunIdx (1)
    - LogPath (auto), LogFile (auto)
    - FilterICAOn (true), FilterICALocutoff (1)
    - ICAType ('runica')
    - ICLabelOn (true), ICLabelThreshold (default matrix)
    - FASTEROn (true)
    - EOGChanLabel ({})
    - DetectECG (true), ECG_Struct ([]), ECGCorrelationThreshold (0.8)

### Channel selection/interp
- remove_channels: drop channels by index or label
  - args: ChanIdx ([]), Chan2remove ({}), LogFile (auto)
- select_channels: keep only selected channels
  - args: ChanIdx ([]), ChanLabels ({}), LogFile (auto)
- interpolate: interpolate channels (uses EEG.badchan etc.)
  - args: LogFile (auto)
- interpolate_bad_channels_epoch: interpolate per epoch
  - args: ExcludeLabel ({}), LogFile (auto)

### Other steps
- reref: average reference with exclusions
  - args: ExcludeLabel ({}), LogFile (auto)
- correct_baseline: baseline correction
  - args: BaselineWindow ([start end] ms, default []), LogFile (auto)
- edit_chantype: set channel types
  - args: EOGLabel ({}), ECGLabel ({}), OtherLabel ({}), LogFile (auto)
- insert_relative_markers: create markers relative to an existing marker
  - args: ReferenceMarker (''), RefOccurrence ('first'), StartOffsetSec (0),
          DurationSec ([]), EndOffsetSec ([]),
          NewStartMarker ('clip_start'), NewEndMarker ('clip_end'),
          OverwriteExisting (true), LogFile (auto)

----------------------------------------------------------------------
## End-to-end prep usage (script style)

This matches `test/prep_end_to_end.m`:

```matlab
repoRoot   = getenv('EEGFLOW_ROOT');
dataDir    = fullfile(repoRoot, 'test', 'data', 'raw');
outDir     = fullfile(repoRoot, 'test', 'out', 'prep_run');
configPath = fullfile(repoRoot, 'config_template', 'prep_config.json');

cfg = flow.load_cfg(configPath);

% Pick input file by regex (adjust pattern to your dataset)
[paths, names] = filesearch_regexp(dataDir, '^sub-.*\\.set$', 1);
if isempty(names), error('No .set files found.'); end

% Fill IO + logging fields
cfg = prep.setup_io(cfg, ...
    'InputPath', paths{1}, ...
    'InputFilename', names{1}, ...
    'OutputPath', outDir, ...
    'Suffix', '_cleaned');

% Build pipeline (prep registry used by default)
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
- register_new_op errors on duplicates unless AllowOverride = true.

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

- +prep: preprocessing steps and helpers
- +analysis: analysis steps and helpers
- config_template: job/config templates
- utils: general utilities
