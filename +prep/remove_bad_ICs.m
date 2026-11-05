function state = remove_bad_ICs(state, args, meta)
%REMOVE_BAD_ICS Detect and remove artifactual ICs from state.EEG.
%
% Purpose & behavior
%   Optionally high-pass filters data for ICA, recomputes ICA, then
%   identifies bad components using ICLabel, FASTER component properties,
%   and/or ECG correlation. Marked components are removed with pop_subcomp.
%
% Flow/state contract
%   Required input state fields:
%     - state.EEG (continuous or epoched with valid chanlocs)
%   Updated/created state fields:
%     - state.EEG (ICA weights + components removed)
%     - state.EEG.etc.EEGdojo.BadICs_run_*
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
%   - BrainIncludeTreshold
%       Type: numeric; Default: 0.7
%       When ICLabel is enabled, protect ICs with brain probability above this
%       threshold from FASTER/ECG rejection.
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
%       Type: numeric; Shape: scalar; Range: > 0, <= 1; Default: 0.8
%       Absolute correlation threshold for ECG rejection.
% Outputs
%   state (struct)
%     - Updated flow state (see Flow/state contract above).
%
% Side effects
%   state.EEG updated; history includes BadICs and the ICA run label.
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

    % Control and I/O
    p.addParameter('RunIdx', 1, @(x) isnumeric(x) && isscalar(x) && x > 0);
    p.addParameter('LogPath', pwd, @(s) ischar(s) || isstring(s));
    p.addParameter('LogFile', '', @(s) ischar(s) || isstring(s));

    % ICA parameters
    p.addParameter('FilterICAOn', true, @islogical);
    p.addParameter('FilterICALocutoff', 1, @(x) isnumeric(x) && isscalar(x) && x > 0);
    p.addParameter('ICAType', 'runica', @ischar);

    % ICLabel parameters
    p.addParameter('ICLabelOn', true, @islogical);
    p.addParameter('ICLabelThreshold', [NaN NaN; 0.7 1; 0.7 1; 0.7 1; 0.7 1; 0.7 1; NaN NaN], @isnumeric);

    % FASTER parameters
    p.addParameter('FASTEROn', true, @islogical);
    p.addParameter('BrainIncludeTreshold', 0.7, @(x) isnumeric(x) && isscalar(x) && x > 0 && x <= 1);
    p.addParameter('EOGChanLabel', {}, @iscellstr);

    % ECG detection parameters
    p.addParameter('DetectECG', true, @islogical);
    p.addParameter('ECGCorrelationThreshold', 0.8, @(x) isnumeric(x) && isscalar(x) && x > 0 && x <= 1);
    p.addParameter('ECG_Struct', [], @(x) isstruct(x) || isempty(x)); % New parameter for separate ECG EEG structure

    nv = state_struct2nv(params);
    state_require_eeg(state, op);
    EEG = state.EEG;
    p.parse(EEG, nv{:});
    R = p.Results;

    if isfield(meta, 'validate_only') && meta.validate_only
        state = state_update_history(state, op, state_strip_eeg_param(R), 'validated', struct());
        return;
    end

    % --------- Setup ----------
    BadICs = struct('IClabel', [], 'FASTER', [], 'ECG', [], 'all', []);
    icaLabel = sprintf('ICA%d', R.RunIdx);

    if ~exist(R.LogPath, 'dir')& ~isempty(R.LogPath), mkdir(R.LogPath); end


        if ~R.ICLabelOn && ~R.FASTEROn && ~R.DetectECG
            error('[remove_bad_ICs] At least one detection method (ICLabel, FASTER, or DetectECG) must be enabled.');
        end

        % Find EOG channels based on provided labels
        EOGChan = [];
        if ~isempty(R.EOGChanLabel)
            for i = 1:length(R.EOGChanLabel)
                idx = find(strcmp({EEG.chanlocs.labels}, R.EOGChanLabel{i}), 1);
                if ~isempty(idx)
                    EOGChan = [EOGChan, idx];
                end
            end
        end

        if isempty(EOGChan)
            if R.FASTEROn
                log_step(state, meta, R.LogFile,'[remove_bad_ICs] FASTER is on, but no EOG channels found with provided labels. Skipping FASTER.');
            end
            R.FASTEROn = false;
        end

        % Check if a separate ECG EEG structure is provided
        if isempty(R.ECG_Struct) || isempty(R.ECG_Struct.data)
            if R.DetectECG
                sprintf('[remove_bad_ICs] DetectECG is on, but no separate ECG EEG structure (ECG_Struct) or its data was provided. Skipping ECG detection.');
            end
            R.DetectECG = false;
        end

        %% --------- Run ICA ----------
        log_step(state, meta, R.LogFile, '[remove_bad_ICs] Checking ICA decomposition...');
        if size(EEG.data, 3) > 1
            tmpdata = reshape(EEG.data, [EEG.nbchan, EEG.pnts * EEG.trials]);
            pca_dim = min(EEG.nbchan-1, getrank(tmpdata));
        else
            pca_dim = min(EEG.nbchan-1, getrank(EEG.data));
        end

        if R.FilterICAOn
            log_step(state, meta, R.LogFile, '[remove_bad_ICs] Applying high-pass filter and computing ICA...');
            filterEEG = pop_eegfiltnew(EEG, 'locutoff', R.FilterICALocutoff, 'plotfreqz', 0);
            filterEEG = pop_runica(filterEEG, 'icatype', R.ICAType, 'extended', 1, 'interrupt', 'off', 'pca', pca_dim);
            EEG.icaweights = filterEEG.icaweights;
            EEG.icasphere = filterEEG.icasphere;
            EEG.icachansind = filterEEG.icachansind;
            EEG.icawinv = filterEEG.icawinv;
            EEG.icaact = eeg_getica(EEG);
            EEG = eeg_checkset(EEG);
            log_step(state, meta, R.LogFile, '[remove_bad_ICs] ICA computed with filtering.');
        else
            log_step(state, meta, R.LogFile, '[remove_bad_ICs] Computing ICA without filtering...');
            EEG = pop_runica(EEG, 'icatype', R.ICAType, 'extended', 1, 'interrupt', 'off', 'pca', pca_dim);
            log_step(state, meta, R.LogFile, '[remove_bad_ICs] ICA computed.');
        end

        %% --------- ICLabel Detection ----------
        if R.ICLabelOn
            log_step(state, meta, R.LogFile, '[remove_bad_ICs] Running ICLabel detection...');
            EEG = pop_iclabel(EEG, 'default');
            EEG = pop_icflag(EEG, R.ICLabelThreshold);
            BadICs.IClabel = find(EEG.reject.gcompreject == 1)';
            if ~isempty(BadICs.IClabel)
                log_step(state, meta, R.LogFile, sprintf('[remove_bad_ICs] ICLabel identified %d bad ICs. Generating property plots...', length(BadICs.IClabel)));
                for i = 1:length(BadICs.IClabel)
                    icIdx = BadICs.IClabel(i);
                    pop_prop(EEG, 0, icIdx, NaN, {'freqrange', [2 40]});
                    batch_saveas(gcf, fullfile(R.LogPath, sprintf('%s_BadICs_IClabel_%d_Properties.png', icaLabel, icIdx)));
                    close(gcf);
                end
            else
                log_step(state, meta, R.LogFile, '[remove_bad_ICs] ICLabel found no bad ICs.');
            end
        end

        %% --------- FASTER Detection ----------
        if R.FASTEROn
            log_step(state, meta, R.LogFile, '[remove_bad_ICs] Running FASTER detection...');
            ICA_list = component_properties(EEG, EOGChan);
            BadICs_tmp = find(min_z(ICA_list) == 1)';

            if R.ICLabelOn
                BadICs.FASTER = [];
                if ~isempty(BadICs_tmp)
                    for i = 1:length(BadICs_tmp)
                        icIdx = BadICs_tmp(i);
                        if EEG.etc.ic_classification.ICLabel.classifications(icIdx, 1) <= R.BrainIncludeTreshold
                            BadICs.FASTER = [BadICs.FASTER, icIdx];
                        end
                    end
                end
            else
                BadICs.FASTER = BadICs_tmp;
            end

            if ~isempty(BadICs.FASTER)
                log_step(state, meta, R.LogFile, sprintf('[remove_bad_ICs] FASTER identified %d bad ICs. Generating property plots...', length(BadICs.FASTER)));
                for i = 1:length(BadICs.FASTER)
                    icIdx = BadICs.FASTER(i);
                    pop_prop(EEG, 0, icIdx, NaN, {'freqrange', [2 40]});
                    batch_saveas(gcf, fullfile(R.LogPath, sprintf('%s_BadICs_FASTER_%d_Properties.png', icaLabel, icIdx)));
                    close(gcf);
                end
            else
                log_step(state, meta, R.LogFile, '[remove_bad_ICs] FASTER found no bad ICs.');
            end
        end

        %% --------- ECG Correlation Detection ----------
        if R.DetectECG
            log_step(state, meta, R.LogFile, '[remove_bad_ICs] Running ECG correlation detection...');

            EEG.icaact = eeg_getica(EEG);

            % --- shapes & alignment checks ---
            % EEG.icaact: [nIC x T]
            % ecg_data:   [nECG x T]  (from R.ECG_Struct.data)
            if size(EEG.icaact, 2) ~= size(R.ECG_Struct.data, 2)
                error('[remove_bad_ICs] ECG and ICA time lengths differ: IC T=%d, ECG T=%d.', ...
                    size(EEG.icaact,2), size(R.ECG_Struct.data,2));
            end

            X = double(EEG.icaact);          % [nIC x T]
            E = double(R.ECG_Struct.data);   % [nECG x T]

            % Z-score along time to handle offset/scale; NaNs for zero-variance rows
            Xz = zscore(X, 0, 2);
            Ez = zscore(E, 0, 2);

            % Replace NaNs (flat channels/components) with 0 so they don’t contribute
            Xz(~isfinite(Xz)) = 0;
            Ez(~isfinite(Ez)) = 0;

            % Correlation of standardized series: (Xz * Ez')/(T-1)
            T  = size(Xz, 2);
            Rm = (Xz * Ez.') / max(T - 1, 1);     % [nIC x nECG]
            Rabs = abs(Rm);

            % Decide bad ICs: max |r| across ECG channels
            rmax = max(Rabs, [], 2);              % [nIC x 1]
            bad_mask = rmax > R.ECGCorrelationThreshold;
            BadICs_tmp1 = find(bad_mask).';        % row vector of IC indices

            if R.ICLabelOn
                BadICs.ECG  = [];
                if ~isempty(BadICs_tmp1)
                    for i = 1:length(BadICs_tmp1)
                        icIdx = BadICs_tmp1(i);
                        if EEG.etc.ic_classification.ICLabel.classifications(icIdx, 1) <= R.BrainIncludeTreshold
                            BadICs.ECG = [BadICs.ECG, icIdx];
                        end
                    end
                end
            else
                BadICs.ECG = BadICs_tmp1;
            end

            if ~isempty(BadICs.ECG)
                log_step(state, meta, R.LogFile, sprintf('[remove_bad_ICs] ECG correlation identified %d bad ICs. Generating property plots...', length(BadICs.ECG)));
                for i = 1:length(BadICs.ECG)
                    icIdx = BadICs.ECG(i);
                    pop_prop(EEG, 0, icIdx, NaN, {'freqrange', [2 40]});
                    batch_saveas(gcf, fullfile(R.LogPath, sprintf('%s_BadICs_ECG_%d_Properties.png', icaLabel, icIdx)));
                    close(gcf);
                end
            else
                log_step(state, meta, R.LogFile, '[remove_bad_ICs] ECG correlation found no bad ICs.');
            end
        end





        %% --------- Combine, Visualize, and Remove ----------
        BadICs.all = unique([BadICs.IClabel, BadICs.FASTER, BadICs.ECG]);
        EEG.reject.gcompreject(BadICs.all) = 1;

        if ~isempty(BadICs.all)
            log_step(state, meta, R.LogFile, sprintf('[remove_bad_ICs] Total unique bad ICs identified: %d. Generating visualization plots...', length(BadICs.all)));
            nComps = size(EEG.icaweights, 1);
            for i = 1:ceil(nComps / 35)
                startIdx = (i-1)*35 + 1;
                endIdx = min(i*35, nComps);
                draw_selectcomps(EEG, startIdx:endIdx);
                batch_saveas(gcf, fullfile(R.LogPath, sprintf('%s_reject_p%d.png', icaLabel, i)));
                close(gcf);
            end
            log_step(state, meta, R.LogFile, sprintf('[remove_bad_ICs] Removing %d bad ICs...', length(BadICs.all)));
            EEG = pop_subcomp(EEG, BadICs.all, 0);
            EEG = eeg_checkset(EEG);
            log_step(state, meta, R.LogFile, '[remove_bad_ICs] Bad ICs removed successfully.');
        else
            log_step(state, meta, R.LogFile, '[remove_bad_ICs] No bad ICs to remove.');
        end

        %% --------- Bookkeeping and Logging ----------
        fieldName = sprintf('BadICs_run_%d', R.RunIdx);
        if ~isfield(EEG.etc, 'EEGdojo'), EEG.etc.EEGdojo = struct(); end
        EEG.etc.EEGdojo.(fieldName) = BadICs;

        out.BadICs = BadICs;
        out.icaLabel = icaLabel;

        log_step(state, meta, R.LogFile, sprintf('[remove_bad_ICs] ================= ICA %s =================', icaLabel));
        log_step(state, meta, R.LogFile, sprintf('[remove_bad_ICs] %s rank: %d', icaLabel, pca_dim));
        log_step(state, meta, R.LogFile, sprintf('[remove_bad_ICs] %s Bad ICs Identified by ICLabel: %d Details: %s', icaLabel, length(BadICs.IClabel), mat2str(BadICs.IClabel)));
        log_step(state, meta, R.LogFile, sprintf('[remove_bad_ICs] %s Bad ICs Identified by FASTER: %d Details: %s', icaLabel, length(BadICs.FASTER), mat2str(BadICs.FASTER)));
        if R.DetectECG
            log_step(state, meta, R.LogFile, sprintf('[remove_bad_ICs] %s Bad ICs Identified by ECG correlation: %d Details: %s', icaLabel, length(BadICs.ECG), mat2str(BadICs.ECG)));
        end
        log_step(state, meta, R.LogFile, sprintf('[remove_bad_ICs] %s Total Unique Bad ICs: %d Details: %s', icaLabel, length(BadICs.all), mat2str(BadICs.all)));

    state.EEG = EEG;
    state = state_update_history(state, op, state_strip_eeg_param(R), 'success', out);

end
