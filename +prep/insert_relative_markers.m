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
    if ~isempty(DurationSec) && ~isempty(EndOffsetSec)
        error('[insert_relative_markers] DurationSec and EndOffsetSec are mutually exclusive.');
    end

    evtype = {state.EEG.event.type};
    for i = 1:numel(evtype)
        if ~(ischar(evtype{i}) || isstring(evtype{i}))
            evtype{i} = num2str(evtype{i});
        else
            evtype{i} = char(evtype{i});
        end
    end
    lat_all = [state.EEG.event.latency];

    ref_idx = find(strcmp(evtype, ReferenceMarker));
    if isempty(ref_idx)
        error('[insert_relative_markers] Reference marker "%s" not found.', ReferenceMarker);
    end
    if strcmp(RefOccurrence, 'last')
        ref_idx = ref_idx(end);
    else
        ref_idx = ref_idx(1);
    end
    ref_samp = lat_all(ref_idx);
    ref_sec  = ref_samp / state.EEG.srate;

    new_start_samp = ref_samp + round(StartOffsetSec * state.EEG.srate);
    new_start_sec  = new_start_samp / state.EEG.srate;

    if ~isempty(DurationSec)
        new_end_samp = new_start_samp + round(DurationSec * state.EEG.srate);
    elseif ~isempty(EndOffsetSec)
        new_end_samp = ref_samp + round(EndOffsetSec * state.EEG.srate);
    else
        new_end_samp = [];
    end
    if ~isempty(new_end_samp)
        new_end_sec = new_end_samp / state.EEG.srate;
    else
        new_end_sec = [];
    end

    if Overwrite
        if ~isempty(NewStartMarker)
            state.EEG.event = state.EEG.event(~strcmp(evtype, NewStartMarker));
        end
        if ~isempty(NewEndMarker)
            state.EEG.event = state.EEG.event(~strcmp(evtype, NewEndMarker));
        end
    end

    if ~isempty(NewStartMarker)
        state.EEG.event(end+1).type = NewStartMarker;
        state.EEG.event(end).latency = new_start_samp;
    end
    if ~isempty(NewEndMarker) && ~isempty(new_end_samp)
        state.EEG.event(end+1).type = NewEndMarker;
        state.EEG.event(end).latency = new_end_samp;
    end

    state.EEG = eeg_checkset(state.EEG, 'eventconsistency');

    out = struct();
    out.ref_marker = ReferenceMarker;
    out.ref_occurrence = RefOccurrence;
    out.ref_sample = ref_samp;
    out.ref_latency_sec = ref_sec;
    out.new_start_marker = NewStartMarker;
    out.new_start_sample = new_start_samp;
    out.new_start_latency_sec = new_start_sec;
    out.new_end_marker = NewEndMarker;
    out.new_end_sample = new_end_samp;
    out.new_end_latency_sec = new_end_sec;
    if ~isempty(DurationSec)
        out.mode = 'ref+startOffset+duration';
    elseif ~isempty(EndOffsetSec)
        out.mode = 'ref+startOffset+endOffset';
    else
        out.mode = 'ref+startOffset';
    end

    logPrint(LogFile, sprintf('[insert_relative_markers] Inserted markers: start=%s end=%s', NewStartMarker, NewEndMarker));
    state = state_update_history(state, op, state_strip_eeg_param(R), 'success', out);
end
