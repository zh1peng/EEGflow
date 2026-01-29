function [EEG, out] = crop_by_markers(EEG, varargin)
% CROP_BY_MARKERS Crops EEG data based on specified start and/or end markers.
%   Extracts a segment between StartMarker and EndMarker with optional padding.
%   If only StartMarker is provided, crops from (Start - PadSec) to the end.
%   If only EndMarker is provided, crops from the beginning to (End + PadSec).
%
% Syntax:
%   [EEG, out] = prep.crop_by_markers(EEG, 'param', value, ...)
%
% Inputs:
%   EEG             - EEGLAB EEG structure.
%
% Name-Value parameters:
%   'StartMarker'   - (char|string, default: '') start event label.
%   'EndMarker'     - (char|string, default: '') end event label.
%   'PadSec'        - (numeric, default: 0) padding (s) added before start and/or after end.
%   'LogFile'       - (char|string, default: '') path to log file ('' -> command window).
%
% Outputs:
%   EEG             - Cropped EEGLAB EEG structure.
%   out             - Struct with:
%                       .mode          - 'start_end' | 'start_only' | 'end_only'
%                       .start_sample  - used start sample (NaN if none)
%                       .end_sample    - used end sample (NaN if none)
%                       .pad_samples   - padding in samples (non-negative)
%
% Examples:
%   % 1) Between two markers with 1s padding
%   EEG = prep.crop_by_markers(EEG, 'StartMarker','start_exp', 'EndMarker','end_exp', 'PadSec',1);
%
%   % 2) Start-only (EGI style): trim everything before start (keep from start-0.5s to end)
%   EEG = prep.crop_by_markers(EEG, 'StartMarker','segment_begin', 'PadSec',0.5);
%
%   % 3) End-only: keep beginning up to end+0.25s
%   EEG = prep.crop_by_markers(EEG, 'EndMarker','segment_end', 'PadSec',0.25);
%
% See also: pop_select, eeg_checkset

    % -------- Parse inputs --------
    p = inputParser;
    p.addRequired('EEG', @isstruct);
    p.addParameter('StartMarker', '', @(s) ischar(s) || isstring(s));
    p.addParameter('EndMarker',   '', @(s) ischar(s) || isstring(s));
    p.addParameter('PadSec',      0,  @isnumeric);
    p.addParameter('LogFile',     '', @(s) ischar(s) || isstring(s));
    p.parse(EEG, varargin{:});
    R = p.Results;

    StartMarker = char(R.StartMarker);
    EndMarker   = char(R.EndMarker);
    PadTime     = R.PadSec;
    LogFile     = R.LogFile;

    pad_samp    = max(0, round(PadTime * EEG.srate));
    out = struct('mode','', 'start_sample',NaN, 'end_sample',NaN, 'pad_samples',pad_samp);

    % -------- Normalize event types to char --------
    evtype = {EEG.event.type};
    for i = 1:numel(evtype)
        if ~(ischar(evtype{i}) || isstring(evtype{i}))
            evtype{i} = num2str(evtype{i});
        else
            evtype{i} = char(evtype{i});
        end
    end
    lat_all = [EEG.event.latency];

    hasStart = ~isempty(strtrim(StartMarker));
    hasEnd   = ~isempty(strtrim(EndMarker));

    if ~hasStart && ~hasEnd
        error('[crop_by_markers] At least one of StartMarker or EndMarker must be specified.');
    end

    % -------- Locate markers (first occurrence for start; last-after-start for end) --------
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
            end_idx  = end_after(end);  % last occurrence after start
            end_samp = lat_all(end_idx);
        else
            % End-only: take the first occurrence (or choose last—first is typical)
            end_idx  = find(strcmp(evtype, EndMarker), 1, 'first');
            if isempty(end_idx)
                error('[crop_by_markers] End marker "%s" not found in EEG events.', EndMarker);
            end
            end_samp = lat_all(end_idx);
        end
    end

    % -------- Determine crop window --------
    if hasStart && hasEnd
        seg_start = max(1, start_samp - pad_samp);
        seg_end   = min(EEG.pnts, end_samp + pad_samp);
        out.mode  = 'start_end';
        logPrint(LogFile, sprintf('[crop_by_markers] Cropping between "%s" and "%s" with %.2fs padding (samples: %d).', ...
            StartMarker, EndMarker, PadTime, pad_samp));

    elseif hasStart && ~hasEnd
        % Start-only: trim pre-start, keep from (start - pad) to end
        seg_start = max(1, start_samp - pad_samp);
        seg_end   = EEG.pnts;
        out.mode  = 'start_only';
        logPrint(LogFile, sprintf('[crop_by_markers] Start-only crop at "%s" with %.2fs padding before start. Keeping from sample %d to end.', ...
            StartMarker, PadTime, seg_start));

    else % ~hasStart && hasEnd
        % End-only: keep from beginning to (end + pad)
        seg_start = 1;
        seg_end   = min(EEG.pnts, end_samp + pad_samp);
        out.mode  = 'end_only';
        logPrint(LogFile, sprintf('[crop_by_markers] End-only crop at "%s" with %.2fs padding after end. Keeping from beginning to sample %d.', ...
            EndMarker, PadTime, seg_end));
    end

    % Sanity check
    if ~(seg_start < seg_end)
        error('[crop_by_markers] Invalid crop window: start (%d) >= end (%d). Check markers and PadSec.', seg_start, seg_end);
    end

    % -------- Apply cropping --------
    EEG = pop_select(EEG, 'point', [seg_start, seg_end]);
    EEG = eeg_checkset(EEG);

    % -------- Outputs --------
    out.start_sample = seg_start;
    out.end_sample   = seg_end;
    logPrint(LogFile, sprintf('[crop_by_markers] Cropped successfully: [%d, %d] (%.2fs).', ...
        seg_start, seg_end, (seg_end - seg_start + 1)/EEG.srate));
end
