function state = remove_bad_epoch(state, args, meta)
%REMOVE_BAD_EPOCH Detect and remove bad epochs from epoched EEG.
%
% Purpose & behavior
%   Uses pop_autorej and/or FASTER epoch_properties to flag bad epochs.
%   Removes them via pop_select and maintains a stable TrialID mapping in
%   EEG.etc.EEGdojo for traceability across QC steps.
%
% Flow/state contract
%   Required input state fields:
%     - state.EEG (epoched)
%   Updated/created state fields:
%     - state.EEG (epochs removed)
%     - state.EEG.etc.EEGdojo.TrialID / RemainTrialID
%     - state.EEG.etc.EEGdojo.BadEpochIdx / BadTrialID*
%     - state.history
%
% Inputs
%   state (struct)
%     - Flow state; see Flow/state contract above.
%   args (struct)
%     - Parameters for this operation (listed below). Merged with state.cfg.remove_bad_epoch if present.
%   meta (struct, optional)
%     - Pipeline meta; supports validate_only/logger.
%
% Parameters
%   - Autorej
%       Type: logical; Default: true
%       Enable pop_autorej detector.
%   - Autorej_MaxRej
%       Type: numeric; Default: 2
%       maxrej for pop_autorej.
%   - FASTER
%       Type: logical; Default: true
%       Enable FASTER epoch_properties detector.
%   - LogFile
%       Type: char|string; Default: ''
%       Optional log file path.
% Outputs
%   state (struct)
%     - Updated flow state (see Flow/state contract above).
%
% Side effects
%   state.EEG updated; history includes Bad/summary.
%
% Usage
%   state = prep.remove_bad_epoch(state, struct('Autorej',true,'FASTER',true));
%
% See also: pop_autorej, epoch_properties, pop_select

    if nargin < 1 || isempty(state), state = struct(); end
    if nargin < 2 || isempty(args), args = struct(); end
    if nargin < 3 || isempty(meta), meta = struct(); end

    op = 'remove_bad_epoch';
    cfg = state_get_config(state, op);
    params = state_merge(cfg, args);

    p = inputParser;
    p.addRequired('EEG', @isstruct);
    p.addParameter('Autorej', true, @islogical);
    p.addParameter('Autorej_MaxRej', 2, @isnumeric);
    p.addParameter('FASTER', true, @islogical);
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
    out = struct();
    logPrint(R.LogFile, 'Identifying bad epochs...');

    if ~isfield(EEG, 'etc') || ~isstruct(EEG.etc), EEG.etc = struct(); end
    if ~isfield(EEG.etc, 'EEGdojo') || ~isstruct(EEG.etc.EEGdojo), EEG.etc.EEGdojo = struct(); end

    nTrials = EEG.trials;
    EEG.urevent = EEG.event;
    if ~isfield(EEG.etc.EEGdojo, 'TrialID') || isempty(EEG.etc.EEGdojo.TrialID)
        EEG.etc.EEGdojo.TrialID = (1:nTrials)';
        EEG.etc.EEGdojo.OrigNTrials = nTrials;
        logPrint(R.LogFile, sprintf('[remove_bad_epoch] Initialized EEGdojo.TrialID (1..%d).', nTrials));
    else
        if numel(EEG.etc.EEGdojo.TrialID) ~= nTrials
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

    TrialID = EEG.etc.EEGdojo.TrialID(:);
    Bad = struct();

    if R.Autorej
        logPrint(R.LogFile, '[remove_bad_epoch] Running pop_autorej detector...');
        [~, Bad.autorej] = pop_autorej(EEG, 'nogui', 'on', 'maxrej', R.Autorej_MaxRej);
        Bad.autorej = Bad.autorej(:)';
    else
        Bad.autorej = [];
    end

    if R.FASTER
        logPrint(R.LogFile, '[remove_bad_epoch] Running FASTER detector...');
        epoch_list = epoch_properties(EEG, 1:EEG.nbchan);
        Bad.FASTER = find(min_z(epoch_list) == 1)';
        Bad.FASTER = Bad.FASTER(:)';
    else
        Bad.FASTER = [];
    end

    Bad.all = unique([Bad.autorej, Bad.FASTER]);
    Bad.all = Bad.all(Bad.all >= 1 & Bad.all <= nTrials);

    summary = struct();
    summary.autorej = numel(Bad.autorej);
    summary.FASTER  = numel(Bad.FASTER);
    summary.Total   = numel(Bad.all);

    logPrint(R.LogFile, sprintf('Bad Epochs Identified by Auto Reject: %d\nDetails: %s', summary.autorej, mat2str(Bad.autorej)));
    logPrint(R.LogFile, sprintf('Bad Epochs Identified by FASTER: %d\nDetails: %s', summary.FASTER,  mat2str(Bad.FASTER)));
    logPrint(R.LogFile, sprintf('Total Unique Bad Epochs: %d\nDetails: %s\n', summary.Total, mat2str(Bad.all)));

    Bad.trial_id = TrialID(Bad.all)';

    if ~isempty(Bad.all)
        logPrint(R.LogFile, sprintf('[remove_bad_epoch] Removing %d bad epochs...', summary.Total));

        keepMask = true(nTrials, 1);
        keepMask(Bad.all) = false;
        keepIdx = find(keepMask);

        EEG = pop_select(EEG, 'notrial', Bad.all);
        EEG = eeg_checkset(EEG);

        EEG.etc.EEGdojo.TrialID = TrialID(keepIdx);
        EEG.etc.EEGdojo.RemainTrialID = EEG.etc.EEGdojo.TrialID;

        logPrint(R.LogFile, '[remove_bad_epoch] Bad epochs removed successfully.');
    else
        logPrint(R.LogFile, '[remove_bad_epoch] No bad epochs to remove.');
        EEG.etc.EEGdojo.RemainTrialID = TrialID;
    end

    out.Bad = Bad;
    out.summary = summary;

    EEG.etc.EEGdojo.BadEpochIdx = Bad.all;
    EEG.etc.EEGdojo.BadEpochSummary = summary;
    EEG.etc.EEGdojo.BadTrialID_auto_thisrun = Bad.trial_id;
    if ~isfield(EEG.etc.EEGdojo, 'BadTrialID_auto_all') || isempty(EEG.etc.EEGdojo.BadTrialID_auto_all)
        EEG.etc.EEGdojo.BadTrialID_auto_all = unique(Bad.trial_id);
    else
        EEG.etc.EEGdojo.BadTrialID_auto_all = unique([EEG.etc.EEGdojo.BadTrialID_auto_all(:); Bad.trial_id(:)]);
        EEG.etc.EEGdojo.BadTrialID_auto_all = EEG.etc.EEGdojo.BadTrialID_auto_all(:)';
    end

    state.EEG = EEG;
    state = state_update_history(state, op, state_strip_eeg_param(R), 'success', out);
end
