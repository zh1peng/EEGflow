function state = crop_by_markers(state, args, meta)
%CROP_BY_MARKERS Crop state.EEG between start/end markers with optional padding.
%
% Purpose & behavior
%   Finds event markers by type and crops the continuous data to a window
%   defined by StartMarker/EndMarker. If only one marker is provided,
%   cropping is from the marker (with padding) to the start/end of the file.
%
% Flow/state contract
%   Required input state fields:
%     - state.EEG (continuous with events)
%   Updated/created state fields:
%     - state.EEG (cropped)
%     - state.history
%
% Inputs
%   state (struct)
%     - Flow state; see Flow/state contract above.
%   args (struct)
%     - Parameters for this operation (listed below). Merged with state.cfg.crop_by_markers if present.
%   meta (struct, optional)
%     - Pipeline meta; supports validate_only/logger.
%
% Parameters
%   - StartMarker
%       Type: char|string; Default: ''
%       Event type to mark the crop start.
%   - EndMarker
%       Type: char|string; Default: ''
%       Event type to mark the crop end.
%   - PadSec
%       Type: numeric; Default: 0
%       Padding in seconds added before start and/or after end.
%   - LogFile
%       Type: char|string; Default: ''
%       Optional log file path.
% Example args
%   args = struct('StartMarker','98','EndMarker','99','PadSec',0.2);
%
% Outputs
%   state (struct)
%     - Updated flow state (see Flow/state contract above).
%
% Side effects
%   state.EEG updated in-place; history includes crop window and mode.
%
% Usage
%   state = prep.crop_by_markers(state, struct('StartMarker','start_exp','EndMarker','end_exp','PadSec',1));
%   state = prep.crop_by_markers(state, struct('StartMarker','segment_begin','PadSec',0.5)); % start-only
%
% See also: pop_select, eeg_checkset, prep.insert_relative_markers

    if nargin < 1 || isempty(state), state = struct(); end
    if nargin < 2 || isempty(args), args = struct(); end
    if nargin < 3 || isempty(meta), meta = struct(); end

    op = 'crop_by_markers';
    cfg = state_get_config(state, op);
    params = state_merge(cfg, args);

    p = inputParser;
    p.addRequired('EEG', @isstruct);
    p.addParameter('StartMarker', '', @(s) ischar(s) || isstring(s));
    p.addParameter('EndMarker',   '', @(s) ischar(s) || isstring(s));
    p.addParameter('PadSec',      0,  @isnumeric);
    p.addParameter('LogFile',     '', @(s) ischar(s) || isstring(s));
    nv = state_struct2nv(params);

    state_require_eeg(state, op);
    p.parse(state.EEG, nv{:});
    R = p.Results;

    if isfield(meta, 'validate_only') && meta.validate_only
        state = state_update_history(state, op, state_strip_eeg_param(R), 'validated', struct());
        return;
    end

    StartMarker = char(R.StartMarker);
    EndMarker   = char(R.EndMarker);
    PadTime     = R.PadSec;
    LogFile     = R.LogFile;

    pad_samp    = max(0, round(PadTime * state.EEG.srate));
    out = struct('mode','', 'start_sample',NaN, 'end_sample',NaN, 'pad_samples',pad_samp);

    evtype = {state.EEG.event.type};
    for i = 1:numel(evtype)
        if ~(ischar(evtype{i}) || isstring(evtype{i}))
            evtype{i} = num2str(evtype{i});
        else
            evtype{i} = char(evtype{i});
        end
    end
    lat_all = [state.EEG.event.latency];

    hasStart = ~isempty(strtrim(StartMarker));
    hasEnd   = ~isempty(strtrim(EndMarker));

    if ~hasStart && ~hasEnd
        error('[crop_by_markers] At least one of StartMarker or EndMarker must be specified.');
    end

    if hasStart
        start_idx = find(strcmp(evtype, StartMarker), 1, 'first');
        if isempty(start_idx)
            error('[crop_by_markers] Start marker "%s" not found in EEG events.', StartMarker);
        end
        start_samp = lat_all(start_idx);
    end

    if hasEnd
        if hasStart
            end_all   = find(strcmp(evtype, EndMarker));
            end_after = end_all(lat_all(end_all) > lat_all(start_idx));
            if isempty(end_after)
                error('[crop_by_markers] End marker "%s" not found after start marker "%s".', EndMarker, StartMarker);
            end
            end_idx  = end_after(end);
            end_samp = lat_all(end_idx);
        else
            end_idx  = find(strcmp(evtype, EndMarker), 1, 'first');
            if isempty(end_idx)
                error('[crop_by_markers] End marker "%s" not found in EEG events.', EndMarker);
            end
            end_samp = lat_all(end_idx);
        end
    end

    if hasStart && hasEnd
        seg_start = max(1, start_samp - pad_samp);
        seg_end   = min(state.EEG.pnts, end_samp + pad_samp);
        out.mode  = 'start_end';
        log_step(state, meta, LogFile, sprintf('[crop_by_markers] Cropping between "%s" and "%s" with %.2fs padding (samples: %d).', ...
            StartMarker, EndMarker, PadTime, pad_samp));
    elseif hasStart && ~hasEnd
        seg_start = max(1, start_samp - pad_samp);
        seg_end   = state.EEG.pnts;
        out.mode  = 'start_only';
        log_step(state, meta, LogFile, sprintf('[crop_by_markers] Start-only crop at "%s" with %.2fs padding before start. Keeping from sample %d to end.', ...
            StartMarker, PadTime, seg_start));
    else
        seg_start = 1;
        seg_end   = min(state.EEG.pnts, end_samp + pad_samp);
        out.mode  = 'end_only';
        log_step(state, meta, LogFile, sprintf('[crop_by_markers] End-only crop at "%s" with %.2fs padding after end. Keeping from beginning to sample %d.', ...
            EndMarker, PadTime, seg_end));
    end

    if ~(seg_start < seg_end)
        error('[crop_by_markers] Invalid crop window: start (%d) >= end (%d). Check markers and PadSec.', seg_start, seg_end);
    end

    state.EEG = pop_select(state.EEG, 'point', [seg_start, seg_end]);
    state.EEG = eeg_checkset(state.EEG);

    out.start_sample = seg_start;
    out.end_sample   = seg_end;
    log_step(state, meta, LogFile, sprintf('[crop_by_markers] Cropped successfully: [%d, %d] (%.2fs).', ...
        seg_start, seg_end, (seg_end - seg_start + 1)/state.EEG.srate));

    state = state_update_history(state, op, state_strip_eeg_param(R), 'success', out);
end
