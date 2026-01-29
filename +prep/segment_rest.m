function [EEG_out, out] = segment_rest(EEG, varargin)
%segment_rest Segment continuous resting EEG into overlapping epochs within EC/EO blocks.
%
% This function is designed for resting-state recordings where EC/EO blocks are
% embedded in a longer continuous EEG stream (e.g., EC–EO–EC–EO), or when a single
% EC/EO block exists. It prevents boundary crossing by cropping each detected
% block first, generating synthetic epoch-start markers *within the cropped block*,
% epoching, and then merging epochs across blocks.
%
% Key features / safeguards
% -------------------------
% 1) Block-aware epoching: epochs are created only within each EC/EO block.
% 2) Non-overlapping pairing: ignores Start events that occur before the previous
%    block has ended.
% 3) Re-runnable: removes any pre-existing 'epoch_start' events before creating new ones.
% 4) Sample-correct epoching: avoids off-by-one sample issues in EEGLAB pop_epoch
%    (epoch window is inclusive).
% 5) Safe merge: blocks that yield 0 epochs are skipped; output is still valid.
%
% Usage
% -----
% (A) Start + End trigger approach (recommended when offsets exist)
%   [EEG_EC, info] = segment_rest(EEG, ...
%       'BlockLabel', "EC", ...
%       'StartCode', 10, ...
%       'EndCode', 11, ...
%       'EpochLength', 2000, ...
%       'EpochOverlap', 0.5, ...
%       'TrimStartSec', 2, ...
%       'TrimEndSec', 2);
%
% (B) Start + fixed duration approach (useful if offsets are missing)
%   [EEG_EO, info] = segment_rest(EEG, ...
%       'BlockLabel', "EO", ...
%       'StartCode', 20, ...
%       'BlockDurSec', 180, ...
%       'EpochLength', 2000, ...
%       'EpochOverlap', 0.5);
%
% Typical parameters
% ------------------
% EpochLength  : 1000–4000 ms (commonly 2000 ms)
% EpochOverlap : 0–0.75 (commonly 0.5 for 50% overlap)
% TrimStartSec : 1–3 s (optional; remove instruction/transition transients)
% TrimEndSec   : 1–3 s (optional)
%
% Inputs
% ------
% EEG : EEGLAB EEG struct (continuous dataset)
%
% Name-Value Parameters
% ---------------------
% BlockLabel     (char/string; default "EC")
%   Label stored into EEG.epoch metadata as rest_label.
%
% StartCode      (numeric/char/string; default 10)
%   Event type that marks the block start (e.g., EC_onset=10, EO_onset=20).
%
% EndCode        (numeric/char/string or []; default [])
%   Event type that marks the block end (e.g., EC_offset=11, EO_offset=21).
%   If empty, BlockDurSec must be provided.
%
% BlockDurSec    (numeric scalar seconds or []; default [])
%   Block duration in seconds used when EndCode is empty.
%
% TrimStartSec   (numeric scalar seconds; default 0)
%   Seconds trimmed off the start of each block after StartCode.
%
% TrimEndSec     (numeric scalar seconds; default 0)
%   Seconds trimmed off the end of each block before EndCode.
%
% EpochLength    (numeric scalar ms; default 2000)
%   Epoch length (ms) for segmentation within each block.
%
% EpochOverlap   (numeric scalar 0<=x<1; default 0.5)
%   Overlap proportion between consecutive epochs. 0.5 = 50% overlap.
%
% LogFile        (char/string; default '')
%   If empty, logs print to command window; otherwise append to file path.
%
% Outputs
% -------
% EEG_out : EEGLAB EEG struct (epoched)
%   Merged across all valid blocks; each epoch has metadata fields:
%     EEG_out.epoch(k).rest_block            : block index (1..N)
%     EEG_out.epoch(k).rest_label            : BlockLabel (e.g., 'EC')
%     EEG_out.epoch(k).rest_block_start_orig : original EEG start point of the block
%     EEG_out.epoch(k).rest_block_end_orig   : original EEG end point of the block
%
% out : struct
%   out.blocks_found          : number of blocks segmented (after trimming/filtering)
%   out.blocks                : [startPoint endPoint] per block (after trimming)
%   out.epochs_per_block      : epochs created per block (0 if skipped)
%   out.epochs_created_total  : total epochs in EEG_out
%
% Notes / Tips
% ------------
% - This function assumes your EEG is already preprocessed as continuous data
%   (filtering, bad channel handling, re-reference, ICA/ASR if used, etc.).
% - Use trimming to avoid instruction and transition periods contaminating resting epochs.
% - For EC/EO interleaved designs, run this once for EC (10–11) and once for EO (20–21)
%   to produce separate epoched datasets.
%
% Dependencies
% ------------
% EEGLAB functions: pop_select, eeg_regepochs, pop_epoch, pop_mergeset, eeg_checkset.
%
% See also: eeg_regepochs, pop_epoch, pop_select

% ----------------- Parse inputs -----------------
p = inputParser;
p.addRequired('EEG', @isstruct);

p.addParameter('BlockLabel', "EC", @(s) ischar(s) || isstring(s));
p.addParameter('StartCode', 10, @(x) isnumeric(x) || ischar(x) || isstring(x));
p.addParameter('EndCode', [], @(x) isempty(x) || isnumeric(x) || ischar(x) || isstring(x));
p.addParameter('BlockDurSec', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));

p.addParameter('TrimStartSec', 0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
p.addParameter('TrimEndSec',   0, @(x) isnumeric(x) && isscalar(x) && x >= 0);

p.addParameter('EpochLength',  2000, @(x) isnumeric(x) && isscalar(x) && x > 0);     % ms
p.addParameter('EpochOverlap', 0.5,  @(x) isnumeric(x) && isscalar(x) && x >= 0 && x < 1);

p.addParameter('LogFile', '', @(s) ischar(s) || isstring(s));
p.parse(EEG, varargin{:});
R = p.Results;

out = struct();
EEG_out = [];

logPrint(R.LogFile, sprintf('[segment_rest] Label=%s | Start=%s | End=%s | BlockDurSec=%s', ...
    string(R.BlockLabel), toStr(R.StartCode), toStr(R.EndCode), toStr(R.BlockDurSec)));

% ----------------- Epoch parameters (sample-safe) -----------------
epochLenSec = R.EpochLength / 1000;
epochLenPts = max(1, round(epochLenSec * EEG.srate));

% pop_epoch uses inclusive [tmin tmax], so set tmax to (N-1)/srate
tmax = (epochLenPts - 1) / EEG.srate;

recurrence_pts = max(1, round(epochLenPts * (1 - R.EpochOverlap)));
recurrence_sec = recurrence_pts / EEG.srate;

if recurrence_sec <= 0
    error('[segment_rest] Invalid recurrence (<=0). Check EpochOverlap/EpochLength.');
end

% ----------------- Find block intervals -----------------
[startLat, ~] = getEventLatencies(EEG, R.StartCode);
startLat = sort(startLat);

if isempty(startLat)
    logPrint(R.LogFile, '[segment_rest] No start events found. Exiting.');
    out.blocks_found = 0;
    out.epochs_created_total = 0;
    return;
end

blocks = [];
last_valid_end = 0;

if ~isempty(R.EndCode)
    [endLat, ~] = getEventLatencies(EEG, R.EndCode);
    endLat = sort(endLat);

    if isempty(endLat)
        error('[segment_rest] EndCode provided but no end events found.');
    end

    for i = 1:numel(startLat)
        s = startLat(i);

        % Ignore starts that happen inside a previous valid block
        if s < last_valid_end
            logPrint(R.LogFile, sprintf('  > Skipping overlapping Start at %d (prev end %d)', s, last_valid_end));
            continue;
        end

        e_candidates = endLat(endLat > s);
        if isempty(e_candidates)
            logPrint(R.LogFile, sprintf('  > WARNING: Start at %d has no subsequent end; skipping.', s));
            continue;
        end

        e = e_candidates(1);
        blocks = [blocks; s, e]; %#ok<AGROW>
        last_valid_end = e;
    end

else
    if isempty(R.BlockDurSec)
        error('[segment_rest] Provide either EndCode or BlockDurSec.');
    end

    durPts = max(1, round(R.BlockDurSec * EEG.srate));

    for i = 1:numel(startLat)
        s = startLat(i);

        if s < last_valid_end
            logPrint(R.LogFile, sprintf('  > Skipping overlapping Start at %d (prev end %d)', s, last_valid_end));
            continue;
        end

        % fixed-duration endpoint is s + durPts - 1 (inclusive)
        e = min(s + durPts - 1, EEG.pnts);
        blocks = [blocks; s, e]; %#ok<AGROW>
        last_valid_end = e;
    end
end

if isempty(blocks)
    logPrint(R.LogFile, '[segment_rest] No valid blocks paired.');
    out.blocks_found = 0;
    out.epochs_created_total = 0;
    return;
end

% ----------------- Apply trimming -----------------
trimS = round(R.TrimStartSec * EEG.srate);
trimE = round(R.TrimEndSec   * EEG.srate);

blocks_trim = blocks;
blocks_trim(:,1) = blocks(:,1) + trimS;
blocks_trim(:,2) = blocks(:,2) - trimE;

% Remove invalid blocks (start must be < end)
blocks_trim = blocks_trim(blocks_trim(:,2) > blocks_trim(:,1), :);

% Filter blocks too short for one epoch
valid = (blocks_trim(:,2) - blocks_trim(:,1) + 1) >= epochLenPts;
blocks_trim = blocks_trim(valid, :);

out.blocks_found = size(blocks_trim, 1);
out.blocks = blocks_trim;

if out.blocks_found == 0
    logPrint(R.LogFile, '[segment_rest] All blocks too short after trimming.');
    out.epochs_created_total = 0;
    return;
end

logPrint(R.LogFile, sprintf('[segment_rest] %d blocks to segment (after trimming).', out.blocks_found));

% ----------------- Segment loop -----------------
valid_EEG_blocks = {};
epochs_per_block = zeros(out.blocks_found, 1);

for b = 1:out.blocks_found
    sPt = blocks_trim(b, 1);
    ePt = blocks_trim(b, 2);

    logPrint(R.LogFile, sprintf('[segment_rest] Block %d: points %d-%d (%.2f s)', ...
        b, sPt, ePt, (ePt - sPt + 1) / EEG.srate));

    % Crop
    try
        EEGb = pop_select(EEG, 'point', [sPt ePt]);
        EEGb = eeg_checkset(EEGb);
    catch ME
        logPrint(R.LogFile, sprintf('  > ERROR selecting block %d: %s', b, ME.message));
        continue;
    end

    % Remove any existing epoch_start events to avoid contamination from prior runs
    if isfield(EEGb, 'event') && ~isempty(EEGb.event)
        evtypes = string({EEGb.event.type});
        keep = evtypes ~= "epoch_start";
        EEGb.event = EEGb.event(keep);
    end

    % Add regularly spaced markers within the block
    EEGb = eeg_regepochs(EEGb, ...
        'recurrence', recurrence_sec, ...
        'eventtype', 'epoch_start', ...
        'extractepochs', 'off');

    % Verify epoch_start events exist (do NOT use isempty(EEGb.event) here)
    if ~isfield(EEGb, 'event') || isempty(EEGb.event)
        logPrint(R.LogFile, sprintf('  > Block %d: no events after regepochs; skipping.', b));
        continue;
    end

    evtypes = string({EEGb.event.type});
    n_epoch_start = sum(evtypes == "epoch_start");
    if n_epoch_start == 0
        logPrint(R.LogFile, sprintf('  > Block %d: no epoch_start events created; skipping.', b));
        continue;
    end

    % Epoch (inclusive window corrected via tmax)
    EEGb = pop_epoch(EEGb, {'epoch_start'}, [0 tmax], 'epochinfo', 'yes');
    EEGb = eeg_checkset(EEGb);

    if EEGb.trials <= 0
        logPrint(R.LogFile, sprintf('  > Block %d: 0 epochs after pop_epoch; skipping.', b));
        continue;
    end

    epochs_per_block(b) = EEGb.trials;

    % Inject epoch-level metadata
    [EEGb.epoch.rest_block] = deal(b);
    [EEGb.epoch.rest_label] = deal(char(R.BlockLabel));
    [EEGb.epoch.rest_block_start_orig] = deal(sPt);
    [EEGb.epoch.rest_block_end_orig]   = deal(ePt);

    valid_EEG_blocks{end+1} = EEGb; %#ok<AGROW>
end

out.epochs_per_block = epochs_per_block;

% ----------------- Safe merge -----------------
if isempty(valid_EEG_blocks)
    logPrint(R.LogFile, '[segment_rest] No epochs generated across all blocks.');
    out.epochs_created_total = 0;
    return;
end

EEG_out = valid_EEG_blocks{1};
for k = 2:numel(valid_EEG_blocks)
    EEG_out = pop_mergeset(EEG_out, valid_EEG_blocks{k}, 0);
end
EEG_out = eeg_checkset(EEG_out);

out.epochs_created_total = EEG_out.trials;
logPrint(R.LogFile, sprintf('[segment_rest] Success. %d epochs created.', out.epochs_created_total));

end

% ----------------- Helpers -----------------
function [lat, idx] = getEventLatencies(EEG, code)
lat = []; idx = [];
if ~isfield(EEG, 'event') || isempty(EEG.event), return; end

targetIsNum = isnumeric(code);
if targetIsNum
    targetNum = code;
else
    targetStr = string(code);
end

for i = 1:numel(EEG.event)
    ev = EEG.event(i).type;
    match = false;

    if targetIsNum
        if isnumeric(ev)
            match = (ev == targetNum);
        elseif ischar(ev) || isstring(ev)
            match = (str2double(ev) == targetNum);
        end
    else
        match = strcmp(string(ev), targetStr);
    end

    if match
        idx(end+1) = i; %#ok<AGROW>
        lat(end+1) = round(double(EEG.event(i).latency)); %#ok<AGROW>
    end
end
end

function logPrint(logFile, msg)
if isempty(logFile)
    fprintf('%s\n', msg);
else
    fid = fopen(logFile, 'a');
    if fid ~= -1
        fprintf(fid, '%s\n', msg);
        fclose(fid);
    else
        fprintf('%s\n', msg);
    end
end
end

function s = toStr(x)
if isempty(x)
    s = "[]";
    return;
end
try
    s = string(x);
catch
    s = "?";
end
end
