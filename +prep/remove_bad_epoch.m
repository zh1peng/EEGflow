function [EEG, out] = remove_bad_epoch(EEG, varargin)
% REMOVE_BAD_EPOCH  Detects and removes bad epochs from an EEG dataset.
%   This function identifies bad epochs using EEGLAB's `pop_autorej` and
%   the FASTER algorithm's `epoch_properties`. It then removes the
%   identified bad epochs from the dataset.
%
% Syntax:
%   [EEG, out] = prep.remove_bad_epoch(EEG, 'param', value, ...)
%
% Input Arguments:
%   EEG         - EEGLAB EEG structure (epoched data).
%
% Optional Parameters (Name-Value Pairs):
%   'Autorej'           - (logical, default: true)
%                         Enable epoch rejection using `pop_autorej`.
%   'Autorej_MaxRej'    - (numeric, default: 2)
%                         `maxrej` parameter for `pop_autorej`.
%   'FASTER'            - (logical, default: true)
%                         Enable epoch rejection using FASTER's `epoch_properties`.
%   'LogFile'           - (char | string, default: '')
%                         File path to log the results.
%
% Output Arguments:
%   EEG         - Modified EEGLAB EEG structure with bad epochs removed.
%   out         - Structure containing details of the detection:
%                 out.Bad.autorej: Indices of bad epochs from `pop_autorej`.
%                 out.Bad.FASTER: Indices of bad epochs from FASTER.
%                 out.Bad.all: Combined unique indices of all bad epochs.
%                 out.summary: Summary of bad epochs per detector and total.

% Adds robust bookkeeping for trial traceability across multiple QC stages:
%   - EEG.etc.EEGdojo.TrialID: length(EEG.trials) vector mapping current epoch index
%     -> original trial id (stable across subsequent rejections)
%   - EEG.etc.EEGdojo.BadEpochIdx: bad epoch indices in CURRENT dataset space (this run)
%   - EEG.etc.EEGdojo.BadTrialID_auto_thisrun: bad trial IDs in ORIGINAL space (this run)
%   - EEG.etc.EEGdojo.BadTrialID_auto_all: accumulated unique bad trial IDs (original space)
%   - EEG.etc.EEGdojo.RemainTrialID: same as TrialID after removal (for convenience)
%
% See also: pop_autorej, epoch_properties, pop_select

     % ----------------- Parse inputs -----------------
    p = inputParser;
    p.addRequired('EEG', @isstruct);
    p.addParameter('Autorej', true, @islogical);
    p.addParameter('Autorej_MaxRej', 2, @isnumeric);
    p.addParameter('FASTER', true, @islogical);
    p.addParameter('LogFile', '', @(s) ischar(s) || isstring(s));
    p.parse(EEG, varargin{:});
    R = p.Results;

    out = struct(); % Initialize out struct
    logPrint(R.LogFile, 'Identifying bad epochs...');

    % ----------------- Ensure EEG.etc.EEGdojo + TrialID mapping -----------------
    if ~isfield(EEG, 'etc') || ~isstruct(EEG.etc), EEG.etc = struct(); end
    if ~isfield(EEG.etc, 'EEGdojo') || ~isstruct(EEG.etc.EEGdojo), EEG.etc.EEGdojo = struct(); end

    nTrials = EEG.trials;
    EEG.urevent = EEG.event;
    % Initialize stable original trial id mapping if missing
    if ~isfield(EEG.etc.EEGdojo, 'TrialID') || isempty(EEG.etc.EEGdojo.TrialID)
        EEG.etc.EEGdojo.TrialID = (1:nTrials)';
        EEG.etc.EEGdojo.OrigNTrials = nTrials;
        logPrint(R.LogFile, sprintf('[remove_bad_epoch] Initialized EEGdojo.TrialID (1..%d).', nTrials));
    else
        % Sanity check
        if numel(EEG.etc.EEGdojo.TrialID) ~= nTrials
            % Fallback: re-init, but warn (mapping may be invalid if prior steps deleted epochs without updating TrialID)
            logPrint(R.LogFile, sprintf(['[remove_bad_epoch] WARNING: EEGdojo.TrialID length (%d) ~= EEG.trials (%d). ' ...
                                         'Re-initializing TrialID to 1..%d (traceability may be compromised).'], ...
                                         numel(EEG.etc.EEGdojo.TrialID), nTrials, nTrials));
            EEG.etc.EEGdojo.TrialID = (1:nTrials)';
            if ~isfield(EEG.etc.EEGdojo, 'OrigNTrials') || isempty(EEG.etc.EEGdojo.OrigNTrials)
                EEG.etc.EEGdojo.OrigNTrials = nTrials;
            end
            out.warn_trialid_reset = true;
        end
    end

    TrialID = EEG.etc.EEGdojo.TrialID(:); % current->original mapping (column)

    % ----------------- Run Detectors -----------------
    Bad = struct();

    if R.Autorej
        logPrint(R.LogFile, '[remove_bad_epoch] Running pop_autorej detector...');
        [~, Bad.autorej] = pop_autorej(EEG, 'nogui', 'on', 'maxrej', R.Autorej_MaxRej);
        Bad.autorej = Bad.autorej(:)'; % row
    else
        Bad.autorej = [];
    end

    if R.FASTER
        logPrint(R.LogFile, '[remove_bad_epoch] Running FASTER detector...');
        epoch_list = epoch_properties(EEG, 1:EEG.nbchan);
        Bad.FASTER = find(min_z(epoch_list) == 1)';
        Bad.FASTER = Bad.FASTER(:)'; % row
    else
        Bad.FASTER = [];
    end

    % ----------------- Combine & Summarize -----------------
    Bad.all = unique([Bad.autorej, Bad.FASTER]);
    Bad.all = Bad.all(Bad.all >= 1 & Bad.all <= nTrials); % guard

    summary = struct();
    summary.autorej = numel(Bad.autorej);
    summary.FASTER  = numel(Bad.FASTER);
    summary.Total   = numel(Bad.all);

    logPrint(R.LogFile, sprintf('Bad Epochs Identified by Auto Reject: %d\nDetails: %s', summary.autorej, mat2str(Bad.autorej)));
    logPrint(R.LogFile, sprintf('Bad Epochs Identified by FASTER: %d\nDetails: %s', summary.FASTER,  mat2str(Bad.FASTER)));
    logPrint(R.LogFile, sprintf('Total Unique Bad Epochs: %d\nDetails: %s\n', summary.Total, mat2str(Bad.all)));

    % Map CURRENT bad epoch indices -> ORIGINAL trial IDs (stable)
    Bad.trial_id = TrialID(Bad.all)'; % row in original space

    % ----------------- Action: Remove -----------------
    if ~isempty(Bad.all)
        logPrint(R.LogFile, sprintf('[remove_bad_epoch] Removing %d bad epochs...', summary.Total));

        keepMask = true(nTrials, 1);
        keepMask(Bad.all) = false;
        keepIdx = find(keepMask);

        EEG = pop_select(EEG, 'notrial', Bad.all);
        EEG = eeg_checkset(EEG);

        % Update TrialID mapping to match the post-removal dataset
        EEG.etc.EEGdojo.TrialID = TrialID(keepIdx);
        EEG.etc.EEGdojo.RemainTrialID = EEG.etc.EEGdojo.TrialID; % alias for convenience

        logPrint(R.LogFile, '[remove_bad_epoch] Bad epochs removed successfully.');
    else
        logPrint(R.LogFile, '[remove_bad_epoch] No bad epochs to remove.');
        EEG.etc.EEGdojo.RemainTrialID = TrialID; % unchanged
    end

    % ----------------- Bookkeeping in EEG.etc -----------------
    out.Bad = Bad;
    out.summary = summary;

    % Keep your original fields, but make them explicit about indexing space
    EEG.etc.EEGdojo.BadEpochIdx = Bad.all; % CURRENT dataset indices (this run)
    EEG.etc.EEGdojo.BadEpochSummary = summary;

    % Store original-space IDs for modeling alignment
    EEG.etc.EEGdojo.BadTrialID_auto_thisrun = Bad.trial_id;

    % Accumulate across multiple calls (optional but useful)
    if ~isfield(EEG.etc.EEGdojo, 'BadTrialID_auto_all') || isempty(EEG.etc.EEGdojo.BadTrialID_auto_all)
        EEG.etc.EEGdojo.BadTrialID_auto_all = unique(Bad.trial_id);
    else
        EEG.etc.EEGdojo.BadTrialID_auto_all = unique([EEG.etc.EEGdojo.BadTrialID_auto_all(:); Bad.trial_id(:)]);
        EEG.etc.EEGdojo.BadTrialID_auto_all = EEG.etc.EEGdojo.BadTrialID_auto_all(:)'; % row
    end

end