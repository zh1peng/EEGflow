function state = remove_bad_ICs(state, args, meta)
%REMOVE_BAD_ICS Detect and remove artifactual ICs from state.EEG.
%
% Purpose & behavior
%   Optionally high-pass filters data for ICA, runs ICA if needed, then
%   identifies bad components using ICLabel, FASTER component properties,
%   and/or ECG correlation. Marked components are removed with pop_subcomp.
%
% Flow/state contract
%   Required input state fields:
%     - state.EEG (continuous or epoched with valid chanlocs)
%   Updated/created state fields:
%     - state.EEG (ICA weights + components removed)
%     - state.EEG.etc.EEGdojo.BadICs_ICA*
%     - state.history
%
% Inputs
%   state (struct)
%     - Flow state; see Flow/state contract above.
%   args (struct)
%     - Parameters for this operation (listed below). Merged with state.cfg.remove_bad_ICs if present.
%   meta (struct, optional)
%     - Pipeline meta; supports validate_only/logger.
%
% Parameters
%   - RunIdx
%       Type: numeric; Shape: scalar; Range: > 0; Default: 1
%       Label for ICA run (stored as ICA1, ICA2, ... in EEG.etc.EEGdojo).
%   - LogPath
%       Type: char|string; Default: pwd
%       Folder for plots/reports.
%   - LogFile
%       Type: char|string; Default: ''
%       Log file path.
%   - FilterICAOn
%       Type: logical; Default: true
%       If true, apply high-pass filter before ICA.
%   - FilterICALocutoff
%       Type: numeric; Shape: scalar; Range: > 0; Default: 1
%       High-pass cutoff in Hz for ICA preparation.
%   - ICAType
%       Type: char; Default: 'runica'
%       ICA algorithm for pop_runica.
%   - ICLabelOn
%       Type: logical; Default: true
%       Enable ICLabel-based rejection.
%   - ICLabelThreshold
%       Type: numeric; Default: [NaN NaN; 0.7 1; 0.7 1; 0.7 1; 0.7 1; 0.7 1; NaN NaN]
%       Thresholds applied to ICLabel class probabilities.
%   - FASTEROn
%       Type: logical; Default: true
%       Enable FASTER component property rejection.
%   - EOGChanLabel
%       Type: char|string; Default: {}
%       EOG channel labels for FASTER metrics.
%   - DetectECG
%       Type: logical; Default: true
%       Enable ECG correlation rejection.
%   - ECG_Struct
%       Type: struct; Default: []
%       Separate EEG struct containing ECG channel data.
%   - ECGCorrelationThreshold
%       Type: numeric; Shape: scalar; Range: >= 0, <= 1; Default: 0.8
%       Absolute correlation threshold for ECG rejection.
% Outputs
%   state (struct)
%     - Updated flow state (see Flow/state contract above).
%
% Side effects
%   state.EEG updated; history includes BadICs + detectors used.
%
% Usage
%   state = prep.remove_bad_ICs(state, struct('ICLabelOn',true,'FASTEROn',true));
%   state = prep.remove_bad_ICs(state, struct('DetectECG',true,'ECG_Struct',ecgEEG));
%
% See also: pop_runica, pop_iclabel, component_properties, pop_subcomp

    if nargin < 1 || isempty(state), state = struct(); end
    if nargin < 2 || isempty(args), args = struct(); end
    if nargin < 3 || isempty(meta), meta = struct(); end

    op = 'remove_bad_ICs';
    cfg = state_get_config(state, op);
    params = state_merge(cfg, args);

    p = inputParser;
    p.addRequired('EEG', @isstruct);

    p.addParameter('RunIdx', 1, @(x) isnumeric(x) && isscalar(x) && x > 0);
    p.addParameter('LogPath', pwd, @(s) ischar(s) || isstring(s));
    p.addParameter('LogFile', '', @(s) ischar(s) || isstring(s));

    p.addParameter('FilterICAOn', true, @islogical);
    p.addParameter('FilterICALocutoff', 1, @(x) isnumeric(x) && isscalar(x) && x > 0);
    p.addParameter('ICAType', 'runica', @ischar);

    p.addParameter('ICLabelOn', true, @islogical);
    p.addParameter('ICLabelThreshold', [NaN NaN; 0.7 1; 0.7 1; 0.7 1; 0.7 1; 0.7 1; NaN NaN], @isnumeric);

    p.addParameter('FASTEROn', true, @islogical);
    p.addParameter('EOGChanLabel', {}, @(x) iscell(x) || ischar(x) || isstring(x));

    p.addParameter('DetectECG', true, @islogical);
    p.addParameter('ECG_Struct', [], @(x) isempty(x) || isstruct(x));
    p.addParameter('ECGCorrelationThreshold', 0.8, @(x) isnumeric(x) && isscalar(x) && x >= 0 && x <= 1);

    nv = state_struct2nv(params);
    state_require_eeg(state, op);
    p.parse(state.EEG, nv{:});
    R = p.Results;

    if isfield(meta, 'validate_only') && meta.validate_only
        state = state_update_history(state, op, state_strip_eeg_param(R), 'validated', struct());
        return;
    end

    EEG = state.EEG;

    % Original logic starts here (unchanged except for EEG variable usage)
    out = struct();
    if ~exist(R.LogPath,'dir') && ~isempty(R.LogPath), mkdir(R.LogPath); end

    if ~isfield(EEG, 'etc') || ~isstruct(EEG.etc), EEG.etc = struct(); end
    if ~isfield(EEG.etc, 'EEGdojo') || ~isstruct(EEG.etc.EEGdojo), EEG.etc.EEGdojo = struct(); end

    icaLabel = sprintf('ICA%d', R.RunIdx);
    out.icaLabel = icaLabel;

    if R.FilterICAOn
        log_step(state, meta, R.LogFile, sprintf('[remove_bad_ICs] Applying high-pass filter at %.2f Hz before ICA...', R.FilterICALocutoff));
        EEG_filt = pop_eegfiltnew(EEG, 'locutoff', R.FilterICALocutoff, 'plotfreqz', 0);
        EEG_filt = eeg_checkset(EEG_filt);
    else
        EEG_filt = EEG;
    end

    if ~isfield(EEG_filt, 'icaweights') || isempty(EEG_filt.icaweights)
        log_step(state, meta, R.LogFile, sprintf('[remove_bad_ICs] Running ICA (%s)...', R.ICAType));
        EEG_filt = pop_runica(EEG_filt, 'icatype', R.ICAType, 'extended', 1);
    end

    EEG.icaweights = EEG_filt.icaweights;
    EEG.icasphere  = EEG_filt.icasphere;
    EEG.icawinv    = EEG_filt.icawinv;
    EEG.icaact     = EEG_filt.icaact;
    EEG = eeg_checkset(EEG);

    BadICs = struct();
    used = {};

    if R.ICLabelOn
        log_step(state, meta, R.LogFile, '[remove_bad_ICs] Running ICLabel...');
        EEG = pop_iclabel(EEG, 'default');
        class = EEG.etc.ic_classification.ICLabel.classifications;
        thr = R.ICLabelThreshold;
        if size(thr,1) ~= size(class,2)
            error('[remove_bad_ICs] ICLabelThreshold must be %dx2.', size(class,2));
        end
        bad = false(1, size(class,1));
        for k = 1:size(class,2)
            low = thr(k,1);
            high = thr(k,2);
            if ~isnan(low) && ~isnan(high)
                bad = bad | (class(:,k) >= low & class(:,k) <= high);
            end
        end
        BadICs.ICLabel = find(bad)';
        used{end+1} = 'ICLabel';
        log_step(state, meta, R.LogFile, sprintf('[remove_bad_ICs] ICLabel bad ICs: %s', mat2str(BadICs.ICLabel)));
    else
        BadICs.ICLabel = [];
    end

    if R.FASTEROn
        log_step(state, meta, R.LogFile, '[remove_bad_ICs] Running FASTER component properties...');
        if isempty(R.EOGChanLabel)
            eog_idx = [];
        else
            eog_idx = chans2idx(EEG, R.EOGChanLabel, 'MustExist', false);
        end
        comp_list = component_properties(EEG, eog_idx, 1:EEG.nbchan);
        BadICs.FASTER = find(min_z(comp_list) == 1)';
        used{end+1} = 'FASTER';
        log_step(state, meta, R.LogFile, sprintf('[remove_bad_ICs] FASTER bad ICs: %s', mat2str(BadICs.FASTER)));
    else
        BadICs.FASTER = [];
    end

    if R.DetectECG && ~isempty(R.ECG_Struct)
        log_step(state, meta, R.LogFile, '[remove_bad_ICs] Running ECG correlation detection...');
        ecg_eeg = R.ECG_Struct;
        if ~isfield(ecg_eeg, 'data') || isempty(ecg_eeg.data)
            warning('[remove_bad_ICs] ECG_Struct has no data. Skipping ECG detection.');
            BadICs.ECG = [];
        else
            EEG = eeg_getica(EEG);
            ic_act = EEG.icaact;
            if isempty(ic_act)
                ic_act = (EEG.icaweights * EEG.icasphere) * EEG.data(:,:);
            end
            ecg = ecg_eeg.data(:);
            nIC = size(ic_act,1);
            bad = [];
            for k = 1:nIC
                c = corr(ic_act(k,:)', ecg);
                if abs(c) >= R.ECGCorrelationThreshold
                    bad(end+1) = k; %#ok<AGROW>
                end
            end
            BadICs.ECG = unique(bad);
            used{end+1} = 'ECG';
            log_step(state, meta, R.LogFile, sprintf('[remove_bad_ICs] ECG-correlated bad ICs: %s', mat2str(BadICs.ECG)));
        end
    else
        BadICs.ECG = [];
    end

    BadICs.all = unique([BadICs.ICLabel(:); BadICs.FASTER(:); BadICs.ECG(:)])';
    out.BadICs = BadICs;
    out.detectors_used = used;

    if ~isempty(BadICs.all)
        log_step(state, meta, R.LogFile, sprintf('[remove_bad_ICs] Removing %d bad ICs...', numel(BadICs.all)));
        EEG = pop_subcomp(EEG, BadICs.all, 0);
        EEG = eeg_checkset(EEG);
        log_step(state, meta, R.LogFile, '[remove_bad_ICs] Bad ICs removed successfully.');
    else
        log_step(state, meta, R.LogFile, '[remove_bad_ICs] No bad ICs to remove.');
    end

    EEG.etc.EEGdojo.(sprintf('BadICs_%s', icaLabel)) = BadICs;
    EEG.etc.EEGdojo.(sprintf('BadICsDetectors_%s', icaLabel)) = used;

    state.EEG = EEG;
    state = state_update_history(state, op, state_strip_eeg_param(R), 'success', out);
end
