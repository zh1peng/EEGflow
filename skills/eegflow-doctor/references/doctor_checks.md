# EEGflow Doctor: Environment Checklist

Use this checklist inside MATLAB. Run top-to-bottom until the missing dependency is resolved.

## 1) Confirm roots (env vars or user-provided paths)

```matlab
getenv('EEGFLOW_ROOT')
getenv('EEGLAB_ROOT')
getenv('FASTER_ROOT')
```

If any are empty, ask the user for the correct install path(s).

## 2) Add EEGflow to path

```matlab
addpath(genpath(getenv('EEGFLOW_ROOT')))
```

If `EEGFLOW_ROOT` is not set, use the explicit folder:

```matlab
addpath(genpath('C:\path\to\EEGflow'))
```

## 3) Check EEGLAB

```matlab
which pop_loadset -all
which eeglab -all
```

If missing:

```matlab
addpath(genpath(getenv('EEGLAB_ROOT')))
```

## 4) Check FASTER

```matlab
which FASTER_rejchan -all
```

If missing:

```matlab
addpath(genpath(getenv('FASTER_ROOT')))
```

## 5) Check ICLabel (optional but used by remove_bad_ICs)

```matlab
which iclabel -all
```

If missing, add the ICLabel folder to path.

## 6) Check CleanLine (optional; used by remove_powerline with Method='cleanline')

```matlab
which cleanline -all
```

If missing, add the CleanLine folder to path or switch Method='notch'.

## 7) Persist path changes (optional)

```matlab
savepath
```

## 8) Verify EEGflow prep ops are visible

```matlab
which prep.load_set -all
which prep.remove_bad_channels -all
```

If these fail, EEGflow path is not set correctly.
