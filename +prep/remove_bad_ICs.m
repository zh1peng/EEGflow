function [EEG, out] = remove_bad_ICs(EEG, varargin)
% REMOVE_BAD_ICS  Detects and removes artifactual independent components (ICs).
%   This function provides a comprehensive framework for identifying and
%   removing bad ICs from an EEGLAB dataset. It integrates multiple detection
%   methods including ICLabel classification, FASTER component properties,
%   and correlation with ECG channels. The function first performs ICA if
%   not already done, then applies the selected detection algorithms, and
%   finally removes the identified bad ICs from the EEG data.
%
% Syntax:
%   [EEG, out] = prep.remove_bad_ICs(EEG, 'param', value, ...)
%
% Input Arguments:
%   EEG         - EEGLAB EEG structure. Must have ICA decomposition computed
%                 or 'FilterICAOn' set to true to compute it.
%
% Optional Parameters (Name-Value Pairs):
%   'RunIdx'                - (numeric, default: 1)
%                             Index for the current ICA run, used for logging
%                             and bookkeeping in EEG.etc.EEGdojo.
%   'LogPath'               - (char | string, default: pwd)
%                             Path to save log plots and reports.
%   'LogFile'               - (char | string, default: '')
%                             Base name for the log report file.
%
%   %% ICA Parameters
%   'FilterICAOn'           - (logical, default: true)
%                             If true, applies a high-pass filter before ICA
%                             computation to improve ICA decomposition.
%   'FilterICALocutoff'     - (numeric, default: 1)
%                             High-pass filter cutoff frequency (Hz) if
%                             'FilterICAOn' is true.
%   'ICAType'               - (char | string, default: 'runica')
%                             Type of ICA algorithm to use (e.g., 'runica', 'fastica').
%
%   %% ICLabel Parameters
%   'ICLabelOn'             - (logical, default: true)
%                             Enable ICLabel classification for IC rejection.
%   'ICLabelThreshold'      - (numeric array, default: [0 0.1; 0.9 1])
%                             Thresholds for ICLabel classification. A 2x2 matrix
%                             where rows are [lower_bound upper_bound] for
%                             brain/artifact probabilities. E.g., [0 0.1; 0.9 1]
%                             means reject ICs with brain probability < 0.1 AND
%                             artifact probability > 0.9.
%
%   %% FASTER Parameters
%   'FASTEROn'              - (logical, default: true)
%                             Enable FASTER component property analysis for IC rejection.
%   'EOGChanLabel'         - (cell array of strings, default: {})
%                             Cell array of channel labels corresponding to EOG
%                             channels (e.g., {'VEOG', 'HEOG'}). These labels are used to identify EOG channels for FASTER analysis. If empty, FASTER EOG detection will be skipped.
%
%   %% ECG Correlation Detection Parameters
%   'DetectECG'             - (logical, default: true)
%                             Enable ECG correlation-based IC rejection.
%   'ECG_Struct'        - (struct, default: [])
%                             A separate EEGLAB EEG structure containing only the ECG channel data. This is used for correlating IC activations with ECG. If not provided, ECG detection will be skipped.
%   'ECGCorrelationThreshold'- (numeric, default: 0.8)
%                             Absolute correlation threshold for ECG detection.
%                             ICs with correlation above this value are marked bad.
%
% Output Arguments:
%   EEG         - Modified EEGLAB EEG structure with bad ICs removed.
%   out         - Structure containing details of the detection:
%                 out.BadICs: Structure with indices of bad ICs per detector.
%                 out.BadICs.all: Combined unique indices of all bad ICs.
%                 out.icaLabel: String identifier for the ICA run (e.g., 'ICA1').
%
% Examples:
%   % Example 1: Remove bad ICs using ICLabel and FASTER (without pipeline)
%   % Assume EEG has ICA computed (e.g., EEG = pop_runica(EEG, 'extended', 1);)
%   % Or set 'FilterICAOn', true to compute ICA within this function.
%   [EEG_cleaned, ic_info] = prep.remove_bad_ICs(EEG, ...
%       'ICLabelOn', true, 'ICLabelThreshold', [0 0.1; 0.9 1], ...
%       'FASTEROn', true, 'EOGChanLabel', {'VEOG', 'HEOG'}, ...
%       'LogPath', 'C:\temp\eeg_logs', 'LogFile', 'bad_ics_report');
%   disp('Total bad ICs removed:');
%   disp(ic_info.BadICs.all);
%
% Example 2 — Remove bad ICs using ECG correlation (with pipeline)
% Assumes:
%   - 'pipe' is an initialized pipeline object
%   - 'ecg_eeg_data' is an EEG struct containing only the ECG channel(s)
% pipe = pipe.addStep(@prep.remove_bad_ICs, ...
%     'DetectECG', true, ...
%     'ECGCorrelationThreshold', 0.75, ...
%     'ECG_Struct', ecg_eeg_data, ...      % pass separate ECG EEG struct
%     'ICLabelOn', false, ...                  % disable ICLabel
%     'FASTEROn', false, ...                   % disable FASTER
%     'RunIdx', 2, ...                         % use the 2nd ICA run
%     'LogPath', 'C:\temp\eeg_logs', ...
%     'LogFile', 'ecg_ics_report');
% Run the pipeline
% [EEG_processed, results] = pipe.run(EEG);

% Notes:
% - Removed ICs are reflected in EEG_processed.icaweights and EEG_processed.icasphere.
% - 'results' (if implemented) may include indices of removed ICs and QC metrics.
% See also: pop_iclabel, pop_icflag, component_properties, pop_eegfiltnew, pop_runica, pop_subcomp, eeg_getica, draw_selectcomps

    % --------- Parse inputs ----------
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

    p.parse(EEG, varargin{:});
    R = p.Results;

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
                logPrint(R.LogFile,'[remove_bad_ICs] FASTER is on, but no EOG channels found with provided labels. Skipping FASTER.');
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
        logPrint(R.LogFile, '[remove_bad_ICs] Checking ICA decomposition...');
        if size(EEG.data, 3) > 1
            tmpdata = reshape(EEG.data, [EEG.nbchan, EEG.pnts * EEG.trials]);
            pca_dim = min(EEG.nbchan-1, getrank(tmpdata));
        else
            pca_dim = min(EEG.nbchan-1, getrank(EEG.data));
        end

        if R.FilterICAOn
            logPrint(R.LogFile, '[remove_bad_ICs] Applying high-pass filter and computing ICA...');
            filterEEG = pop_eegfiltnew(EEG, 'locutoff', R.FilterICALocutoff, 'plotfreqz', 0);
            filterEEG = pop_runica(filterEEG, 'icatype', R.ICAType, 'extended', 1, 'interrupt', 'off', 'pca', pca_dim);
            EEG.icaweights = filterEEG.icaweights;
            EEG.icasphere = filterEEG.icasphere;
            EEG.icachansind = filterEEG.icachansind;
            EEG.icawinv = filterEEG.icawinv;
            EEG.icaact = eeg_getica(EEG);
            EEG = eeg_checkset(EEG);
            logPrint(R.LogFile, '[remove_bad_ICs] ICA computed with filtering.');
        else
            logPrint(R.LogFile, '[remove_bad_ICs] Computing ICA without filtering...');
            EEG = pop_runica(EEG, 'icatype', R.ICAType, 'extended', 1, 'interrupt', 'off', 'pca', pca_dim);
            logPrint(R.LogFile, '[remove_bad_ICs] ICA computed.');
        end

        %% --------- ICLabel Detection ----------
        if R.ICLabelOn
            logPrint(R.LogFile, '[remove_bad_ICs] Running ICLabel detection...');
            EEG = pop_iclabel(EEG, 'default');
            EEG = pop_icflag(EEG, R.ICLabelThreshold);
            BadICs.IClabel = find(EEG.reject.gcompreject == 1)';
            if ~isempty(BadICs.IClabel)
                logPrint(R.LogFile, sprintf('[remove_bad_ICs] ICLabel identified %d bad ICs. Generating property plots...', length(BadICs.IClabel)));
                for i = 1:length(BadICs.IClabel)
                    icIdx = BadICs.IClabel(i);
                    pop_prop(EEG, 0, icIdx, NaN, {'freqrange', [2 40]});
                    batch_saveas(gcf, fullfile(R.LogPath, sprintf('%s_BadICs_IClabel_%d_Properties.png', icaLabel, icIdx)));
                    close(gcf);
                end
            else
                logPrint(R.LogFile, '[remove_bad_ICs] ICLabel found no bad ICs.');
            end
        end

        %% --------- FASTER Detection ----------
        if R.FASTEROn
            logPrint(R.LogFile, '[remove_bad_ICs] Running FASTER detection...');
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
                logPrint(R.LogFile, sprintf('[remove_bad_ICs] FASTER identified %d bad ICs. Generating property plots...', length(BadICs.FASTER)));
                for i = 1:length(BadICs.FASTER)
                    icIdx = BadICs.FASTER(i);
                    pop_prop(EEG, 0, icIdx, NaN, {'freqrange', [2 40]});
                    batch_saveas(gcf, fullfile(R.LogPath, sprintf('%s_BadICs_FASTER_%d_Properties.png', icaLabel, icIdx)));
                    close(gcf);
                end
            else
                logPrint(R.LogFile, '[remove_bad_ICs] FASTER found no bad ICs.');
            end
        end

        %% --------- ECG Correlation Detection ----------
        if R.DetectECG
            logPrint(R.LogFile, '[remove_bad_ICs] Running ECG correlation detection...');

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
                logPrint(R.LogFile, sprintf('[remove_bad_ICs] ECG correlation identified %d bad ICs. Generating property plots...', length(BadICs.ECG)));
                for i = 1:length(BadICs.ECG)
                    icIdx = BadICs.ECG(i);
                    pop_prop(EEG, 0, icIdx, NaN, {'freqrange', [2 40]});
                    batch_saveas(gcf, fullfile(R.LogPath, sprintf('%s_BadICs_ECG_%d_Properties.png', icaLabel, icIdx)));
                    close(gcf);
                end
            else
                logPrint(R.LogFile, '[remove_bad_ICs] ECG correlation found no bad ICs.');
            end
        end





        %% --------- Combine, Visualize, and Remove ----------
        BadICs.all = unique([BadICs.IClabel, BadICs.FASTER, BadICs.ECG]);
        EEG.reject.gcompreject(BadICs.all) = 1;

        if ~isempty(BadICs.all)
            logPrint(R.LogFile, sprintf('[remove_bad_ICs] Total unique bad ICs identified: %d. Generating visualization plots...', length(BadICs.all)));
            nComps = size(EEG.icaweights, 1);
            for i = 1:ceil(nComps / 35)
                startIdx = (i-1)*35 + 1;
                endIdx = min(i*35, nComps);
                draw_selectcomps(EEG, startIdx:endIdx);
                batch_saveas(gcf, fullfile(R.LogPath, sprintf('%s_reject_p%d.png', icaLabel, i)));
                close(gcf);
            end
            logPrint(R.LogFile, sprintf('[remove_bad_ICs] Removing %d bad ICs...', length(BadICs.all)));
            EEG = pop_subcomp(EEG, BadICs.all, 0);
            EEG = eeg_checkset(EEG);
            logPrint(R.LogFile, '[remove_bad_ICs] Bad ICs removed successfully.');
        else
            logPrint(R.LogFile, '[remove_bad_ICs] No bad ICs to remove.');
        end

        %% --------- Bookkeeping and Logging ----------
        fieldName = sprintf('BadICs_run_%d', R.RunIdx);
        if ~isfield(EEG.etc, 'EEGdojo'), EEG.etc.EEGdojo = struct(); end
        EEG.etc.EEGdojo.(fieldName) = BadICs;

        out.BadICs = BadICs;
        out.icaLabel = icaLabel;

        logPrint(R.LogFile, sprintf('[remove_bad_ICs] ================= ICA %s =================', icaLabel));
        logPrint(R.LogFile, sprintf('[remove_bad_ICs] %s rank: %d', icaLabel, pca_dim));
        logPrint(R.LogFile, sprintf('[remove_bad_ICs] %s Bad ICs Identified by ICLabel: %d Details: %s', icaLabel, length(BadICs.IClabel), mat2str(BadICs.IClabel)));
        logPrint(R.LogFile, sprintf('[remove_bad_ICs] %s Bad ICs Identified by FASTER: %d Details: %s', icaLabel, length(BadICs.FASTER), mat2str(BadICs.FASTER)));
        if R.DetectECG
            logPrint(R.LogFile, sprintf('[remove_bad_ICs] %s Bad ICs Identified by ECG correlation: %d Details: %s', icaLabel, length(BadICs.ECG), mat2str(BadICs.ECG)));
        end
        logPrint(R.LogFile, sprintf('[remove_bad_ICs] %s Total Unique Bad ICs: %d Details: %s', icaLabel, length(BadICs.all), mat2str(BadICs.all)));

end