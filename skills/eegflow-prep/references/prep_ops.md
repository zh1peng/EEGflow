# Prep Ops Reference (EEGflow)

Defaults are from each op's inputParser. LogFile/LogPath are auto-injected by `prep.setup_io`.

## I/O

- load_set: load EEGLAB .set
  - args: filename (char, default ''), filepath (char, default ''), LogFile (auto)
- load_mff: load EGI .mff
  - args: filename (char, default ''), filepath (char, default ''), LogFile (auto)
- save_set: save EEGLAB .set
  - args: filename (char, default ''), filepath (char, default ''), LogFile (auto)

## Basic signal ops

- downsample
  - args: Rate (numeric, default 250), LogFile (auto)
- filter
  - args: LowCutoff (numeric, default -1), HighCutoff (numeric, default -1), LogFile (auto)
- remove_powerline
  - args: Method ('cleanline'|'notch', default 'cleanline'), Freq (50), BW (2), NHarm (3), LogFile (auto)

## Segmentation

- crop_by_markers
  - args: StartMarker (char, default ''), EndMarker (char, default ''), PadSec (0), LogFile (auto)
- segment_task
  - args: Markers (cellstr, default {}), TimeWindow (ms [start end], default []), LogFile (auto)
- segment_rest
  - args: BlockLabel ("EC"), StartCode (10), EndCode ([]), BlockDurSec ([]),
          TrimStartSec (0), TrimEndSec (0), EpochLength (2000 ms),
          EpochOverlap (0.5), LogFile (auto)

## Cleaning

- remove_bad_channels
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
- remove_bad_epoch
  - args: Autorej (true), Autorej_MaxRej (2), FASTER (true), LogFile (auto)
- remove_bad_ICs
  - args:
    - RunIdx (1)
    - LogPath (auto), LogFile (auto)
    - FilterICAOn (true), FilterICALocutoff (1)
    - ICAType ('runica')
    - ICLabelOn (true), ICLabelThreshold (default matrix)
    - FASTEROn (true)
    - EOGChanLabel ({})
    - DetectECG (true), ECG_Struct ([]), ECGCorrelationThreshold (0.8)

## Channel selection/interp

- remove_channels
  - args: ChanIdx ([]), Chan2remove ({}), LogFile (auto)
- select_channels
  - args: ChanIdx ([]), ChanLabels ({}), LogFile (auto)
- interpolate
  - args: LogFile (auto)
- interpolate_bad_channels_epoch
  - args: ExcludeLabel ({}), LogFile (auto)

## Other

- reref
  - args: ExcludeLabel ({}), LogFile (auto)
- correct_baseline
  - args: BaselineWindow ([start end] ms, default []), LogFile (auto)
- edit_chantype
  - args: EOGLabel ({}), ECGLabel ({}), OtherLabel ({}), LogFile (auto)
- insert_relative_markers
  - args: ReferenceMarker (''), RefOccurrence ('first'), StartOffsetSec (0),
          DurationSec ([]), EndOffsetSec ([]),
          NewStartMarker ('clip_start'), NewEndMarker ('clip_end'),
          OverwriteExisting (true), LogFile (auto)
