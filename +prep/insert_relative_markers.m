function [EEG, out] = insert_relative_markers(EEG, varargin)
% INSERT_RELATIVE_MARKERS Inserts new event markers at latencies defined
% relative to a reference marker (e.g., movie_start) to support creating a
% short clip window.
%
% Typical use:
%   - Find ReferenceMarker (e.g., 'movie_start')
%   - Insert NewStartMarker at ReferenceMarker + StartOffsetSec
%   - Insert NewEndMarker at (NewStartMarker + DurationSec)  OR  (ReferenceMarker + EndOffsetSec)
%
% Syntax:
%   [EEG, out] = prep.insert_relative_markers(EEG, 'param', value, ...)
%
% Inputs:
%   EEG - EEGLAB EEG structure (continuous).
%
% Name-Value parameters:
%   'ReferenceMarker'  - (char|string, required) marker label to anchor from.
%   'RefOccurrence'    - (char|string, default: 'first') 'first' | 'last'
%   'StartOffsetSec'   - (numeric scalar, default: 0) seconds relative to ReferenceMarker.
%   'DurationSec'      - (numeric scalar, default: []) if provided, end = start + DurationSec.
%   'EndOffsetSec'     - (numeric scalar, default: []) if provided, end = ref + EndOffsetSec.
%                        (Mutually exclusive with DurationSec.)
%   'NewStartMarker'   - (char|string, default: 'clip_start') label to insert for new start.
%                        If empty, start marker insertion is skipped.
%   'NewEndMarker'     - (char|string, default: 'clip_end') label to insert for new end.
%                        If empty, end marker insertion is skipped.
%   'OverwriteExisting'- (logical, default: true) remove existing events with same label(s) before inserting.
%   'LogFile'          - (char|string, default: '') log destination ('' -> command window).
%
% Outputs:
%   EEG - EEGLAB EEG structure with inserted event(s).
%   out - Struct with:
%         .ref_marker         .ref_occurrence
%         .ref_sample         .ref_latency_sec
%         .new_start_marker   .new_start_sample   .new_start_latency_sec
%         .new_end_marker     .new_end_sample     .new_end_latency_sec
%         .mode               'ref+startOffset' and end definition info
%
% Example:
%   % new start at +23s from movie_start; new end 171s after new start
%   [EEG, out] = prep.insert_relative_markers(EEG, ...
%       'ReferenceMarker','movie_start', ...
%       'StartOffsetSec',23, ...
%       'DurationSec',171, ...
%       'NewStartMarker','movie_start_clip', ...
%       'NewEndMarker','movie_end_clip', ...
%       'OverwriteExisting',true, ...
%       'LogFile','');
%
% See also: eeg_checkset, pop_select

    % ----------------- Parse inputs -----------------
    p = inputParser;
    p.addRequired('EEG', @isstruct);
    p.addParameter('ReferenceMarker', '', @(s) ischar(s) || isstring(s));
    p.addParameter('RefOccurrence', 'first', @(s) ischar(s) || isstring(s));
    p.addParameter('StartOffsetSec', 0, @(x) isnumeric(x) && isscalar(x));
    p.addParameter('DurationSec', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));
    p.addParameter('EndOffsetSec', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
    p.addParameter('NewStartMarker', 'clip_start', @(s) ischar(s) || isstring(s));
    p.addParameter('NewEndMarker', 'clip_end', @(s) ischar(s) || isstring(s));
    p.addParameter('OverwriteExisting', true, @(x) islogical(x) && isscalar(x));
    p.addParameter('LogFile', '', @(s) ischar(s) || isstring(s));

    p.parse(EEG, varargin{:});
    R = p.Results;

    ReferenceMarker = char(R.ReferenceMarker);
    RefOccurrence   = lower(strtrim(char(R.RefOccurrence)));
    StartOffsetSec  = R.StartOffsetSec;
    DurationSec     = R.DurationSec;
    EndOffsetSec    = R.EndOffsetSec;
    NewStartMarker  = char(R.NewStartMarker);
    NewEndMarker    = char(R.NewEndMarker);
    Overwrite       = R.OverwriteExisting;
    LogFile         = R.LogFile;

    if isempty(strtrim(ReferenceMarker))
        error('[insert_relative_markers] ReferenceMarker must be specified.');
    end
    if ~(strcmp(RefOccurrence,'first') || strcmp(RefOccurrence,'last'))
        error('[insert_relative_markers] RefOccurrence must be "first" or "last".');
    end
    if ~isempty(DurationSec) && ~isempty(EndOffsetSec)
        error('[insert_relative_markers] DurationSec and EndOffsetSec are mutually exclusive. Provide only one.');
    end

    out = struct();
    out.ref_marker       = ReferenceMarker;
    out.ref_occurrence   = RefOccurrence;
    out.ref_sample       = NaN;
    out.ref_latency_sec  = NaN;
    out.new_start_marker = strtrim(NewStartMarker);
    out.new_start_sample = NaN;
    out.new_start_latency_sec = NaN;
    out.new_end_marker   = strtrim(NewEndMarker);
    out.new_end_sample   = NaN;
    out.new_end_latency_sec = NaN;
    out.mode             = '';

    if ~isfield(EEG, 'event') || isempty(EEG.event)
        error('[insert_relative_markers] EEG.event is empty. Cannot insert relative markers without events.');
    end

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

    % -------- Locate reference marker --------
    ref_all = find(strcmp(evtype, ReferenceMarker));
    if isempty(ref_all)
        error('[insert_relative_markers] Reference marker "%s" not found in EEG events.', ReferenceMarker);
    end
    if strcmp(RefOccurrence, 'first')
        ref_idx = ref_all(1);
    else
        ref_idx = ref_all(end);
    end
    ref_samp = lat_all(ref_idx);

    out.ref_sample      = ref_samp;
    out.ref_latency_sec = (ref_samp - 1) / EEG.srate;

    logPrint(LogFile, sprintf('[insert_relative_markers] Reference "%s" (%s) at sample %.0f (%.3fs).', ...
        ReferenceMarker, RefOccurrence, ref_samp, out.ref_latency_sec));

    % -------- Compute new start --------
    hasNewStart = ~isempty(strtrim(NewStartMarker));
    if hasNewStart
        start_samp = round(ref_samp + StartOffsetSec * EEG.srate);

        if start_samp < 1 || start_samp > EEG.pnts
            error('[insert_relative_markers] New start sample %d out of bounds [1, %d]. Check StartOffsetSec.', start_samp, EEG.pnts);
        end

        out.new_start_sample      = start_samp;
        out.new_start_latency_sec = (start_samp - 1) / EEG.srate;
        out.mode = 'ref+startOffset';

        logPrint(LogFile, sprintf('[insert_relative_markers] New start "%s" at ref + %.3fs -> sample %d (%.3fs).', ...
            NewStartMarker, StartOffsetSec, start_samp, out.new_start_latency_sec));
    else
        start_samp = NaN;
        logPrint(LogFile, '[insert_relative_markers] NewStartMarker is empty, skipping start marker insertion.');
    end

    % -------- Compute new end --------
    hasNewEnd = ~isempty(strtrim(NewEndMarker));
    end_samp  = NaN;

    if hasNewEnd
        if ~isempty(DurationSec)
            if ~hasNewStart
                error('[insert_relative_markers] DurationSec requires NewStartMarker (cannot define end from start if start insertion is skipped).');
            end
            end_samp = round(start_samp + DurationSec * EEG.srate);
            out.mode = 'ref+startOffset + duration';
            logPrint(LogFile, sprintf('[insert_relative_markers] End defined as start + %.3fs -> sample %d.', DurationSec, end_samp));

        elseif ~isempty(EndOffsetSec)
            end_samp = round(ref_samp + EndOffsetSec * EEG.srate);
            out.mode = 'ref+startOffset + refEndOffset';
            logPrint(LogFile, sprintf('[insert_relative_markers] End defined as ref + %.3fs -> sample %d.', EndOffsetSec, end_samp));

        else
            logPrint(LogFile, '[insert_relative_markers] Neither DurationSec nor EndOffsetSec provided; skipping end marker insertion.');
            hasNewEnd = false;
        end

        if hasNewEnd
            if end_samp < 1 || end_samp > EEG.pnts
                error('[insert_relative_markers] New end sample %d out of bounds [1, %d]. Check DurationSec/EndOffsetSec.', end_samp, EEG.pnts);
            end
            if hasNewStart && ~(out.new_start_sample < end_samp)
                error('[insert_relative_markers] Invalid window: new start (%d) >= new end (%d).', out.new_start_sample, end_samp);
            end

            out.new_end_sample      = end_samp;
            out.new_end_latency_sec = (end_samp - 1) / EEG.srate;

            logPrint(LogFile, sprintf('[insert_relative_markers] New end "%s" at sample %d (%.3fs).', ...
                NewEndMarker, end_samp, out.new_end_latency_sec));
        end
    else
        logPrint(LogFile, '[insert_relative_markers] NewEndMarker is empty, skipping end marker insertion.');
    end

    % -------- Optionally remove existing markers of same labels --------
    if Overwrite
        rm_types = {};
        if hasNewStart, rm_types{end+1} = strtrim(NewStartMarker); end %#ok<AGROW>
        if hasNewEnd,   rm_types{end+1} = strtrim(NewEndMarker);   end %#ok<AGROW>

        if ~isempty(rm_types)
            keep = true(1, numel(EEG.event));
            for k = 1:numel(rm_types)
                keep = keep & ~strcmp(evtype, rm_types{k});
            end
            if any(~keep)
                logPrint(LogFile, sprintf('[insert_relative_markers] OverwriteExisting=true: removing %d existing event(s) with labels: %s', ...
                    sum(~keep), strjoin(rm_types, ', ')));
                EEG.event = EEG.event(keep);
            end
        end
    end

    % -------- Build event templates (preserve fieldnames) --------
    tmpl = EEG.event(1);
    fn = fieldnames(tmpl);

    make_event = @(label, samp) local_make_event(fn, label, samp);

    % -------- Insert events --------
    n_added = 0;

    if hasNewStart
        EEG.event(end+1) = make_event(strtrim(NewStartMarker), out.new_start_sample);
        n_added = n_added + 1;
    end
    if hasNewEnd
        EEG.event(end+1) = make_event(strtrim(NewEndMarker), out.new_end_sample);
        n_added = n_added + 1;
    end

    if n_added == 0
        logPrint(LogFile, '[insert_relative_markers] No markers inserted (nothing to do).');
        EEG = eeg_checkset(EEG);
        return;
    end

    % -------- Sort events by latency and check consistency --------
    [~, ord] = sort([EEG.event.latency]);
    EEG.event = EEG.event(ord);

    EEG = eeg_checkset(EEG, 'eventconsistency');

    logPrint(LogFile, sprintf('[insert_relative_markers] Inserted %d marker(s). Event consistency check complete.', n_added));
end

% ---- local helper: create event struct with same fields as EEG.event(1) ----
function ev = local_make_event(fn, label, samp)
    ev = struct();
    for ii = 1:numel(fn)
        field = fn{ii};
        if strcmp(field, 'duration')
            ev.(field) = 0; % Explicitly set duration to 0 for instantaneous events
        elseif strcmp(field, 'urevent')
            % obscure edge case: ensure it is empty to prevent linking to wrong raw event
            ev.(field) = []; 
        else
            ev.(field) = [];
        end
    end
    ev.type    = label;
    ev.latency = double(samp);
end