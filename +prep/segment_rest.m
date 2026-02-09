function state = segment_rest(state, args, meta)
%SEGMENT_REST Segment resting-state EEG into overlapping epochs within EC/EO blocks.
%
% Purpose & behavior
%   Finds EC/EO blocks using StartCode + EndCode (or fixed BlockDurSec),
%   trims block edges, generates regularly spaced epoch_start events inside
%   each block, epochs with pop_epoch, and merges all valid blocks.
%
% Flow/state contract
%   Required input state fields:
%     - state.EEG (continuous with events)
%   Updated/created state fields:
%     - state.EEG (epoched)
%     - state.history
%
% Inputs
%   state (struct)
%     - Flow state; see Flow/state contract above.
%   args (struct)
%     - Parameters for this operation (listed below). Merged with state.cfg.segment_rest if present.
%   meta (struct, optional)
%     - Pipeline meta; supports validate_only/logger.
%
% Parameters
%   - BlockLabel
%       Type: char|string; Default: "EC"
%       Label stored into EEG.epoch metadata (rest_label).
%   - StartCode
%       Type: char|string|numeric; Default: 10
%       Event type marking block start.
%   - EndCode
%       Type: char|string|numeric; Default: []
%       Event type marking block end; if empty, BlockDurSec is required.
%   - BlockDurSec
%       Type: numeric; Shape: scalar; Range: > 0; Default: []
%       Fixed duration (s) used when EndCode is empty.
%   - TrimStartSec
%       Type: numeric; Shape: scalar; Range: >= 0; Default: 0
%       Seconds trimmed after block start.
%   - TrimEndSec
%       Type: numeric; Shape: scalar; Range: >= 0; Default: 0
%       Seconds trimmed before block end.
%   - EpochLength
%       Type: numeric; Shape: scalar; Range: > 0; Default: 2000
%       Epoch length in milliseconds.
%   - EpochOverlap
%       Type: numeric; Shape: scalar; Range: >= 0; Default: 0.5
%       Overlap fraction between consecutive epochs.
%   - LogFile
%       Type: char|string; Default: ''
%       Optional log file path.
%   - PreserveICA
%       Type: logical; Shape: scalar; Default: true
%       If true, snapshots ICA fields from input EEG and restores them after
%       block segmentation/merge.
%   - RecomputeICAAct
%       Type: logical; Shape: scalar; Default: false
%       If true and ICA is restored, recomputes EEG.icaact on output.
% Outputs
%   state (struct)
%     - Updated flow state (see Flow/state contract above).
%
% Side effects
%   state.EEG updated; history includes block/epoch counts.
%
% Usage
%   state = prep.segment_rest(state, struct('BlockLabel',"EC",'StartCode',10,'EndCode',11,'EpochLength',2000,'EpochOverlap',0.5));
%
% See also: eeg_regepochs, pop_epoch, pop_select, pop_mergeset

    if nargin < 1 || isempty(state), state = struct(); end
    if nargin < 2 || isempty(args), args = struct(); end
    if nargin < 3 || isempty(meta), meta = struct(); end

    op = 'segment_rest';
    cfg = state_get_config(state, op);
    params = state_merge(cfg, args);

    p = inputParser;
    p.addRequired('EEG', @isstruct);
    p.addParameter('BlockLabel', "EC", @(s) ischar(s) || isstring(s));
    p.addParameter('StartCode', 10, @(x) isnumeric(x) || ischar(x) || isstring(x));
    p.addParameter('EndCode', [], @(x) isempty(x) || isnumeric(x) || ischar(x) || isstring(x));
    p.addParameter('BlockDurSec', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));
    p.addParameter('TrimStartSec', 0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
    p.addParameter('TrimEndSec',   0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
    p.addParameter('EpochLength',  2000, @(x) isnumeric(x) && isscalar(x) && x > 0);
    p.addParameter('EpochOverlap', 0.5,  @(x) isnumeric(x) && isscalar(x) && x >= 0 && x < 1);
    p.addParameter('LogFile', '', @(s) ischar(s) || isstring(s));
    p.addParameter('PreserveICA', true, @(x) islogical(x) && isscalar(x));
    p.addParameter('RecomputeICAAct', false, @(x) islogical(x) && isscalar(x));
    nv = state_struct2nv(params);

    state_require_eeg(state, op);
    EEG = state.EEG;
    p.parse(EEG, nv{:});
    R = p.Results;

    % ----------------- Snapshot ICA from input (optional) -----------------
    icaSnap = struct('has', false);
    if R.PreserveICA
        icaSnap.has = isfield(EEG, 'icaweights') && ~isempty(EEG.icaweights) && ...
                      isfield(EEG, 'icasphere')  && ~isempty(EEG.icasphere)  && ...
                      isfield(EEG, 'icachansind') && ~isempty(EEG.icachansind);

        if icaSnap.has
            icaSnap.icaweights  = EEG.icaweights;
            icaSnap.icasphere   = EEG.icasphere;
            icaSnap.icachansind = EEG.icachansind;

            if isfield(EEG, 'icawinv') && ~isempty(EEG.icawinv)
                icaSnap.icawinv = EEG.icawinv;
            else
                icaSnap.icawinv = [];
            end

            log_step(state, meta, R.LogFile, sprintf('[segment_rest] PreserveICA=ON (ncomp=%d, nch=%d)', ...
                size(icaSnap.icaweights, 1), numel(icaSnap.icachansind)));
        else
            log_step(state, meta, R.LogFile, '[segment_rest] PreserveICA requested but no valid ICA fields found in input EEG.');
        end
    end

    if isfield(meta, 'validate_only') && meta.validate_only
        state = state_update_history(state, op, state_strip_eeg_param(R), 'validated', struct());
        return;
    end

    out = struct();

    log_step(state, meta, R.LogFile, sprintf('[segment_rest] Label=%s | Start=%s | End=%s | BlockDurSec=%s', ...
        string(R.BlockLabel), toStr(R.StartCode), toStr(R.EndCode), toStr(R.BlockDurSec)));

    epochLenSec = R.EpochLength / 1000;
    epochLenPts = max(1, round(epochLenSec * EEG.srate));
    tmax = (epochLenPts - 1) / EEG.srate;
    recurrence_pts = max(1, round(epochLenPts * (1 - R.EpochOverlap)));
    recurrence_sec = recurrence_pts / EEG.srate;

    if recurrence_sec <= 0
        error('[segment_rest] Invalid recurrence (<=0). Check EpochOverlap/EpochLength.');
    end

    [startLat, ~] = getEventLatencies(EEG, R.StartCode);
    startLat = sort(startLat);

    if isempty(startLat)
        log_step(state, meta, R.LogFile, '[segment_rest] No start events found. Exiting.');
        out.blocks_found = 0;
        out.epochs_created_total = 0;
        state = state_update_history(state, op, state_strip_eeg_param(R), 'skipped', out);
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
            if s < last_valid_end
                log_step(state, meta, R.LogFile, sprintf('  > Skipping overlapping Start at %d (prev end %d)', s, last_valid_end));
                continue;
            end
            e_candidates = endLat(endLat > s);
            if isempty(e_candidates)
                log_step(state, meta, R.LogFile, sprintf('  > WARNING: Start at %d has no subsequent end; skipping.', s));
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
                log_step(state, meta, R.LogFile, sprintf('  > Skipping overlapping Start at %d (prev end %d)', s, last_valid_end));
                continue;
            end
            e = min(s + durPts - 1, EEG.pnts);
            blocks = [blocks; s, e]; %#ok<AGROW>
            last_valid_end = e;
        end
    end

    if isempty(blocks)
        log_step(state, meta, R.LogFile, '[segment_rest] No valid blocks paired.');
        out.blocks_found = 0;
        out.epochs_created_total = 0;
        state = state_update_history(state, op, state_strip_eeg_param(R), 'skipped', out);
        return;
    end

    trimS = round(R.TrimStartSec * EEG.srate);
    trimE = round(R.TrimEndSec   * EEG.srate);

    blocks_trim = blocks;
    blocks_trim(:,1) = blocks(:,1) + trimS;
    blocks_trim(:,2) = blocks(:,2) - trimE;
    blocks_trim = blocks_trim(blocks_trim(:,2) > blocks_trim(:,1), :);
    valid = (blocks_trim(:,2) - blocks_trim(:,1) + 1) >= epochLenPts;
    blocks_trim = blocks_trim(valid, :);

    out.blocks_found = size(blocks_trim, 1);
    out.blocks = blocks_trim;

    if out.blocks_found == 0
        log_step(state, meta, R.LogFile, '[segment_rest] All blocks too short after trimming.');
        out.epochs_created_total = 0;
        state = state_update_history(state, op, state_strip_eeg_param(R), 'skipped', out);
        return;
    end

    log_step(state, meta, R.LogFile, sprintf('[segment_rest] %d blocks to segment (after trimming).', out.blocks_found));

    valid_EEG_blocks = {};
    epochs_per_block = zeros(out.blocks_found, 1);

    for b = 1:out.blocks_found
        sPt = blocks_trim(b, 1);
        ePt = blocks_trim(b, 2);
        log_step(state, meta, R.LogFile, sprintf('[segment_rest] Block %d: points %d-%d (%.2f s)', ...
            b, sPt, ePt, (ePt - sPt + 1) / EEG.srate));
        try
            EEGb = pop_select(EEG, 'point', [sPt ePt]);
            EEGb = eeg_checkset(EEGb);
        catch ME
            log_step(state, meta, R.LogFile, sprintf('  > ERROR selecting block %d: %s', b, ME.message));
            continue;
        end

        if isfield(EEGb, 'event') && ~isempty(EEGb.event)
            evtypes = string({EEGb.event.type});
            keep = evtypes ~= "epoch_start";
            EEGb.event = EEGb.event(keep);
        end

        EEGb = eeg_regepochs(EEGb, ...
            'recurrence', recurrence_sec, ...
            'eventtype', 'epoch_start', ...
            'extractepochs', 'off');

        if ~isfield(EEGb, 'event') || isempty(EEGb.event)
            log_step(state, meta, R.LogFile, sprintf('  > Block %d: no events after regepochs; skipping.', b));
            continue;
        end

        evtypes = string({EEGb.event.type});
        n_epoch_start = sum(evtypes == "epoch_start");
        if n_epoch_start == 0
            log_step(state, meta, R.LogFile, sprintf('  > Block %d: no epoch_start events created; skipping.', b));
            continue;
        end

        EEGb = pop_epoch(EEGb, {'epoch_start'}, [0 tmax], 'epochinfo', 'yes');
        EEGb = eeg_checkset(EEGb);

        if EEGb.trials <= 0
            log_step(state, meta, R.LogFile, sprintf('  > Block %d: 0 epochs after pop_epoch; skipping.', b));
            continue;
        end

        epochs_per_block(b) = EEGb.trials;

        [EEGb.epoch.rest_block] = deal(b);
        [EEGb.epoch.rest_label] = deal(char(R.BlockLabel));
        [EEGb.epoch.rest_block_start_orig] = deal(sPt);
        [EEGb.epoch.rest_block_end_orig]   = deal(ePt);

        valid_EEG_blocks{end+1} = EEGb; %#ok<AGROW>
    end

    out.epochs_per_block = epochs_per_block;

    if isempty(valid_EEG_blocks)
        log_step(state, meta, R.LogFile, '[segment_rest] No epochs generated across all blocks.');
        out.epochs_created_total = 0;
        state = state_update_history(state, op, state_strip_eeg_param(R), 'skipped', out);
        return;
    end

    EEG_out = valid_EEG_blocks{1};
    for k = 2:numel(valid_EEG_blocks)
        EEG_out = pop_mergeset(EEG_out, valid_EEG_blocks{k}, 0);
    end
    EEG_out = eeg_checkset(EEG_out);

    % ----------------- Restore ICA + recompute activations -----------------
    if icaSnap.has
        if EEG_out.nbchan ~= EEG.nbchan
            log_step(state, meta, R.LogFile, sprintf(['[segment_rest] WARNING: nbchan changed (in=%d out=%d). ' ...
                'Not restoring ICA.'], EEG.nbchan, EEG_out.nbchan));
        else
            EEG_out.icaweights  = icaSnap.icaweights;
            EEG_out.icasphere   = icaSnap.icasphere;
            EEG_out.icachansind = icaSnap.icachansind;

            if isempty(icaSnap.icawinv)
                W = double(EEG_out.icaweights) * double(EEG_out.icasphere);
                EEG_out.icawinv = pinv(W);
            else
                EEG_out.icawinv = icaSnap.icawinv;
            end

            if R.RecomputeICAAct
                EEG_out.icaact = [];
                EEG_out = recompute_icaact(EEG_out);
                log_step(state, meta, R.LogFile, '[segment_rest] ICA restored + icaact recomputed on EEG_out.');
            else
                log_step(state, meta, R.LogFile, '[segment_rest] ICA restored on EEG_out (RecomputeICAAct=OFF).');
            end
            EEG_out = eeg_checkset(EEG_out);
        end
    end

    out.epochs_created_total = EEG_out.trials;
    log_step(state, meta, R.LogFile, sprintf('[segment_rest] Success. %d epochs created.', out.epochs_created_total));

    state.EEG = EEG_out;
    state = state_update_history(state, op, state_strip_eeg_param(R), 'success', out);
end

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

function EEG = recompute_icaact(EEG)
% Recompute EEG.icaact from current EEG.data using stored ICA unmixing.
% Safe for epoched data (nbchan x pnts x trials).
if ~isfield(EEG, 'icaweights') || isempty(EEG.icaweights) || ...
   ~isfield(EEG, 'icasphere')  || isempty(EEG.icasphere)  || ...
   ~isfield(EEG, 'icachansind')|| isempty(EEG.icachansind)
    return;
end

if any(EEG.icachansind < 1) || any(EEG.icachansind > EEG.nbchan)
    return;
end

W = double(EEG.icaweights) * double(EEG.icasphere);   % comps x chansUsed
X = double(EEG.data(EEG.icachansind, :, :));          % chansUsed x pnts x trials

[ch, pnts, tr] = size(X);
X2 = reshape(X, ch, pnts * tr);

A2 = W * X2;                                           % comps x (pnts*tr)
EEG.icaact = reshape(A2, size(W, 1), pnts, tr);
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
