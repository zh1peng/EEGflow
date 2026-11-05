function state = insert_relative_markers(state, args, meta)
%INSERT_RELATIVE_MARKERS Insert new markers at latencies relative to a reference event.
%
% Purpose & behavior
%   Finds a reference marker and inserts a new start marker at a fixed offset,
%   then inserts an end marker based on either DurationSec or EndOffsetSec.
%   Existing markers with the same labels can be removed first.
%
% Flow/state contract
%   Required input state fields:
%     - state.EEG (continuous with events)
%   Updated/created state fields:
%     - state.EEG.event (new markers inserted)
%     - state.history
%
% Inputs
%   state (struct)
%     - Flow state; see Flow/state contract above.
%   args (struct)
%     - Parameters for this operation (listed below). Merged with state.cfg.insert_relative_markers if present.
%   meta (struct, optional)
%     - Pipeline meta; supports validate_only/logger.
%
% Parameters
%   - ReferenceMarker
%       Type: char|string; Default: ''
%       Event type to anchor from.
%   - RefOccurrence
%       Type: char|string; Default: 'first'
%       Which reference to use: 'first' or 'last'.
%   - StartOffsetSec
%       Type: numeric; Shape: scalar; Default: 0
%       Seconds relative to reference for new start marker.
%   - DurationSec
%       Type: numeric; Shape: scalar; Range: > 0; Default: []
%       If set, end marker is start + DurationSec.
%   - EndOffsetSec
%       Type: numeric; Shape: scalar; Default: []
%       If set, end marker is reference + EndOffsetSec.
%       (Mutually exclusive with DurationSec.)
%   - NewStartMarker
%       Type: char|string; Default: 'clip_start'
%       Label for inserted start marker (empty disables insertion).
%   - NewEndMarker
%       Type: char|string; Default: 'clip_end'
%       Label for inserted end marker (empty disables insertion).
%   - OverwriteExisting
%       Type: logical; Shape: scalar; Default: true
%       Remove pre-existing events with the same labels before inserting.
%   - LogFile
%       Type: char|string; Default: ''
%       Optional log file path.
% Outputs
%   state (struct)
%     - Updated flow state (see Flow/state contract above).
%
% Side effects
%   state.EEG.event updated; history includes inserted marker metadata.
%
% Usage
%   state = prep.insert_relative_markers(state, struct('ReferenceMarker','movie_start', ...
%       'StartOffsetSec',23,'DurationSec',171,'NewStartMarker','movie_start_clip','NewEndMarker','movie_end_clip'));
%
% See also: eeg_checkset, prep.crop_by_markers

    if nargin < 1 || isempty(state), state = struct(); end
    if nargin < 2 || isempty(args), args = struct(); end
    if nargin < 3 || isempty(meta), meta = struct(); end

    op = 'insert_relative_markers';
    cfg = state_get_config(state, op);
    params = state_merge(cfg, args);

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
    nv = state_struct2nv(params);

    state_require_eeg(state, op);
    p.parse(state.EEG, nv{:});
    R = p.Results;

    if isfield(meta, 'validate_only') && meta.validate_only
        state = state_update_history(state, op, state_strip_eeg_param(R), 'validated', struct());
        return;
    end

    EEG = state.EEG;

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

    log_step(state, meta, LogFile, sprintf('[insert_relative_markers] Reference "%s" (%s) at sample %.0f (%.3fs).', ...
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

        log_step(state, meta, LogFile, sprintf('[insert_relative_markers] New start "%s" at ref + %.3fs -> sample %d (%.3fs).', ...
            NewStartMarker, StartOffsetSec, start_samp, out.new_start_latency_sec));
    else
        start_samp = NaN;
        log_step(state, meta, LogFile, '[insert_relative_markers] NewStartMarker is empty, skipping start marker insertion.');
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
            log_step(state, meta, LogFile, sprintf('[insert_relative_markers] End defined as start + %.3fs -> sample %d.', DurationSec, end_samp));

        elseif ~isempty(EndOffsetSec)
            end_samp = round(ref_samp + EndOffsetSec * EEG.srate);
            out.mode = 'ref+startOffset + refEndOffset';
            log_step(state, meta, LogFile, sprintf('[insert_relative_markers] End defined as ref + %.3fs -> sample %d.', EndOffsetSec, end_samp));

        else
            log_step(state, meta, LogFile, '[insert_relative_markers] Neither DurationSec nor EndOffsetSec provided; skipping end marker insertion.');
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

            log_step(state, meta, LogFile, sprintf('[insert_relative_markers] New end "%s" at sample %d (%.3fs).', ...
                NewEndMarker, end_samp, out.new_end_latency_sec));
        end
    else
        log_step(state, meta, LogFile, '[insert_relative_markers] NewEndMarker is empty, skipping end marker insertion.');
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
                log_step(state, meta, LogFile, sprintf('[insert_relative_markers] OverwriteExisting=true: removing %d existing event(s) with labels: %s', ...
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
        log_step(state, meta, LogFile, '[insert_relative_markers] No markers inserted (nothing to do).');
        EEG = eeg_checkset(EEG);
        state.EEG = EEG;
        state = state_update_history(state, op, state_strip_eeg_param(R), 'skipped', out);
        return;
    end

    % -------- Sort events by latency and check consistency --------
    [~, ord] = sort([EEG.event.latency]);
    EEG.event = EEG.event(ord);

    EEG = eeg_checkset(EEG, 'eventconsistency');

    log_step(state, meta, LogFile, sprintf('[insert_relative_markers] Inserted %d marker(s). Event consistency check complete.', n_added));
    state.EEG = EEG;
    state = state_update_history(state, op, state_strip_eeg_param(R), 'success', out);
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
