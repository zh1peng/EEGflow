function state = remove_bad_channels(state, args, meta)
%REMOVE_BAD_CHANNELS Detect and remove/flag bad channels in state.EEG.
%
% Purpose & behavior
%   Runs one or more detectors (EEGLAB pop_rejchan, FASTER, CleanRaw) to
%   identify bad channels, then removes or flags them. Results are stored in
%   EEG.etc.EEGdojo and returned via history metrics.
%
% Flow/state contract
%   Required input state fields:
%     - state.EEG
%   Updated/created state fields:
%     - state.EEG (channels removed or flags added)
%     - state.EEG.etc.EEGdojo.BadChan*
%     - state.history
%
% Inputs
%   state (struct)
%     - Flow state; see Flow/state contract above.
%   args (struct)
%     - Parameters for this operation (listed below). Merged with state.cfg.remove_bad_channels if present.
%   meta (struct, optional)
%     - Pipeline meta; supports validate_only/logger.
%
% Parameters
%   - ExcludeLabel
%       Type: cellstr|char|string; Default: {}
%       Channels excluded from detection.
%   - Action
%       Type: char|string; Default: 'remove'; Options: remove, flag
%       'remove' drops channels; 'flag' sets EEG.etc.clean_channel_mask.
%   - LogPath
%       Type: char|string; Default: ''
%       Folder for plots/reports.
%   - LogFile
%       Type: char|string; Default: ''
%       Log file path.
%   - KnownBadLabel
%       Type: numeric; Default: []
%       Channels known to be bad (included in final list).
%   - Kurtosis
%       Type: logical; Default: false
%       Enable kurtosis-based detector.
%   - Kurt_Threshold
%       Type: numeric; Shape: scalar; Range: > 0; Default: 5
%       Threshold parameter for Kurt_.
%   - Probability
%       Type: logical; Default: false
%       Enable probability-based detector.
%   - Prob_Threshold
%       Type: numeric; Shape: scalar; Range: > 0; Default: 5
%       Threshold parameter for Prob_.
%   - Spectrum
%       Type: logical; Default: false
%       Enable spectrum-based detector.
%   - Spec_Threshold
%       Type: numeric; Shape: scalar; Range: > 0; Default: 5
%       Threshold parameter for Spec_.
%   - Spec_FreqRange
%       Type: numeric; Shape: length 2; Range: >= 0; Default: [1 50]
%       Frequency range [min max] for spectrum detector.
%   - NormOn
%       Type: char|string; Default: 'on'; Options: on, off
%       Normalization mode for detector (on/off).
%   - FASTER_MeanCorr
%       Type: logical; Default: false
%       FASTER parameter: MeanCorr
%   - FASTER_Threshold
%       Type: numeric; Default: 0.4
%       Threshold parameter for FASTER_.
%   - FASTER_RefChan
%       Type: numeric; Shape: scalar; Default: []
%       FASTER parameter: RefChan
%   - FASTER_Bandpass
%       Type: numeric; Shape: length 2; Default: []
%       FASTER parameter: Bandpass
%   - FASTER_Variance
%       Type: logical; Default: false
%       FASTER parameter: Variance
%   - FASTER_VarThreshold
%       Type: numeric; Default: 3
%       Threshold parameter for FASTER_Va.
%   - FASTER_Hurst
%       Type: logical; Default: false
%       FASTER parameter: Hurst
%   - FASTER_HurstThreshold
%       Type: numeric; Default: 3
%       Threshold parameter for FASTER_Hurst.
%   - CleanRaw_Flatline
%       Type: logical; Default: false
%       CleanRaw parameter: Flatline
%   - Flatline_Sec
%       Type: numeric; Shape: scalar; Range: >= 0; Default: 5
%       Parameter for this operation.
%   - CleanDrift_Band
%       Type: numeric; Shape: length 2; Default: [0.25 0.75]
%       Parameter for this operation.
%   - CleanRaw_Noise
%       Type: logical; Default: false
%       CleanRaw parameter: Noise
%   - CleanChan_Corr
%       Type: numeric; Default: 0.8
%       CleanRaw channel parameter: Corr
%   - CleanChan_Line
%       Type: numeric; Default: 4
%       CleanRaw channel parameter: Line
%   - CleanChan_MaxBad
%       Type: numeric; Shape: scalar; Range: >= 0, <= 1; Default: 0.5
%       CleanRaw channel parameter: MaxBad
%   - CleanChan_NSamp
%       Type: numeric; Default: 50
%       CleanRaw channel parameter: NSamp
% Example args
%   args = struct('Action','remove','Kurtosis',true,'Kurt_Threshold',5,'Probability',false,'Spectrum',false,'Spec_FreqRange',[1 50],...
%                'FASTER_MeanCorr',false,'CleanRaw_Flatline',false,'CleanRaw_Noise',false);
%
% Outputs
%   state (struct)
%     - Updated flow state (see Flow/state contract above).
%
% Side effects
%   state.EEG updated; history includes Bad/summary/detectors_used.
%   May write plots/reports to LogPath.
%
% Usage
%   state = prep.remove_bad_channels(state, struct('Kurtosis',true,'Kurt_Threshold',5));
%   state = prep.remove_bad_channels(state, struct('Action','flag','FASTER_MeanCorr',true));
%
% See also: pop_rejchan, FASTER_rejchan, cleanraw_rejchan, logplot_badchannels

    if nargin < 1 || isempty(state), state = struct(); end
    if nargin < 2 || isempty(args), args = struct(); end
    if nargin < 3 || isempty(meta), meta = struct(); end

    op = 'remove_bad_channels';
    cfg = state_get_config(state, op);
    params = state_merge(cfg, args);

    p = inputParser;
    p.addRequired('EEG', @isstruct);
    p.addParameter('ExcludeLabel',      {}, @(x) iscellstr(x) || ischar(x) || isstring(x));
    p.addParameter('Action',            'remove', @(s) any(strcmpi(s,{'remove','flag'})));
    p.addParameter('LogPath',           '', @(s) ischar(s) || isstring(s));
    p.addParameter('LogFile',           '', @(s) ischar(s) || isstring(s));
    p.addParameter('KnownBadLabel',       [], @(x) isempty(x) || isnumeric(x));

    p.addParameter('Kurtosis',          false, @islogical);
    p.addParameter('Kurt_Threshold',    5, @(x)isnumeric(x)&&isscalar(x)&&x>0);
    p.addParameter('Probability',       false, @islogical);
    p.addParameter('Prob_Threshold',    5, @(x)isnumeric(x)&&isscalar(x)&&x>0);
    p.addParameter('Spectrum',          false, @islogical);
    p.addParameter('Spec_Threshold',    5, @(x)isnumeric(x)&&isscalar(x)&&x>0);
    p.addParameter('Spec_FreqRange',    [1 50], @(x)isnumeric(x)&&numel(x)==2&&all(x>=0));
    p.addParameter('NormOn',            'on', @(x) any(strcmpi(x,{'on','off'})));

    p.addParameter('FASTER_MeanCorr',     false, @islogical);
    p.addParameter('FASTER_Threshold',    0.4, @isnumeric);
    p.addParameter('FASTER_RefChan',      [], @(x) isempty(x) || (isscalar(x)&&isnumeric(x)));
    p.addParameter('FASTER_Bandpass',     [], @(x) isempty(x) || (isnumeric(x)&&numel(x)==2));
    p.addParameter('FASTER_Variance',     false, @islogical);
    p.addParameter('FASTER_VarThreshold', 3, @isnumeric);
    p.addParameter('FASTER_Hurst',        false, @islogical);
    p.addParameter('FASTER_HurstThreshold', 3, @isnumeric);

    p.addParameter('CleanRaw_Flatline', false, @islogical);
    p.addParameter('Flatline_Sec',      5, @(x)isnumeric(x)&&isscalar(x)&&x>=0);
    p.addParameter('CleanDrift_Band',   [0.25 0.75], @(x) isempty(x) || (isnumeric(x)&&numel(x)==2));
    p.addParameter('CleanRaw_Noise',    false, @islogical);
    p.addParameter('CleanChan_Corr',    0.8, @isnumeric);
    p.addParameter('CleanChan_Line',    4, @isnumeric);
    p.addParameter('CleanChan_MaxBad',  0.5, @(x)isnumeric(x)&&isscalar(x)&&x>=0&&x<=1);
    p.addParameter('CleanChan_NSamp',   50, @isnumeric);

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

    if ~isempty(R.ExcludeLabel)
        excludeIdx = chans2idx(EEG, R.ExcludeLabel);
        IdxDetect = setdiff(1:EEG.nbchan, excludeIdx);
    else
        IdxDetect = 1:EEG.nbchan;
    end

    if ~isempty(R.KnownBadLabel)
        KnownBadIdx = chans2idx(EEG, R.KnownBadLabel);
    else
        KnownBadIdx = [];
    end

    if ~exist(R.LogPath,'dir') && ~isempty(R.LogPath), mkdir(R.LogPath); end

    EEG.urchanlocs=[];
    [EEG.urchanlocs] = deal(EEG.chanlocs);
    EEG.chaninfo.nodatchans = [];

    Bad  = struct();
    used = {};

    if R.Kurtosis
        log_step(state, meta, R.LogFile, '[remove_bad_channels] Running Kurtosis detector...');
        [~, idxRel] = pop_rejchan(EEG, 'elec', IdxDetect, 'threshold', R.Kurt_Threshold, 'norm', lower(R.NormOn), 'measure', 'kurt');
        Bad.Kurt = IdxDetect(idxRel);
        used{end+1} = 'Kurt';
        logplot_badchannels(EEG, Bad.Kurt, R.LogPath, 'Kurt');
    else
        Bad.Kurt = [];
    end

    if R.Spectrum
        log_step(state, meta, R.LogFile, '[remove_bad_channels] Running Spectrum detector...');
        [~, idxRel] = pop_rejchan(EEG, 'elec', IdxDetect, 'threshold', R.Spec_Threshold, 'norm', lower(R.NormOn), 'measure', 'spec', 'freqrange', R.Spec_FreqRange);
        Bad.Spec = IdxDetect(idxRel);
        used{end+1} = 'Spec';
        logplot_badchannels(EEG, Bad.Spec, R.LogPath, 'Spec');
    else
        Bad.Spec = [];
    end

    if R.Probability
        log_step(state, meta, R.LogFile, '[remove_bad_channels] Running Probability detector...');
        [~, idxRel] = pop_rejchan(EEG, 'elec', IdxDetect, 'threshold', R.Prob_Threshold, 'norm', lower(R.NormOn), 'measure', 'prob');
        Bad.Prob = IdxDetect(idxRel);
        used{end+1} = 'Prob';
        logplot_badchannels(EEG, Bad.Prob, R.LogPath, 'Prob');
    else
        Bad.Prob = [];
    end

    if R.FASTER_MeanCorr
        log_step(state, meta, R.LogFile, '[remove_bad_channels] Running FASTER Mean Correlation detector...');
        args2 = {'elec', IdxDetect, 'measure','meanCorr', 'threshold', R.FASTER_Threshold};
        if ~isempty(R.FASTER_RefChan), args2 = [args2, {'refchan', R.FASTER_RefChan}]; end
        if ~isempty(R.FASTER_Bandpass), args2 = [args2, {'bandpass', R.FASTER_Bandpass}]; end
        [~, idx] = FASTER_rejchan(EEG, args2{:});
        if ~isempty(R.FASTER_RefChan), idx = setdiff(idx, R.FASTER_RefChan); end
        Bad.MeanCorr = idx(:)';
        used{end+1} = 'FASTER_MeanCorr';
        logplot_badchannels(EEG, Bad.MeanCorr, R.LogPath, 'MeanCorr');
    else
        Bad.MeanCorr = [];
    end

    if R.FASTER_Variance
        log_step(state, meta, R.LogFile, '[remove_bad_channels] Running FASTER Variance detector...');
        args2 = {'elec', IdxDetect, 'measure','variance', 'threshold', R.FASTER_VarThreshold};
        if ~isempty(R.FASTER_RefChan), args2 = [args2, {'refchan', R.FASTER_RefChan}]; end
        if ~isempty(R.FASTER_Bandpass), args2 = [args2, {'bandpass', R.FASTER_Bandpass}]; end
        [~, idx] = FASTER_rejchan(EEG, args2{:});
        if ~isempty(R.FASTER_RefChan), idx = setdiff(idx, R.FASTER_RefChan); end
        Bad.Variance = idx(:)';
        used{end+1} = 'FASTER_Variance';
        logplot_badchannels(EEG, Bad.Variance, R.LogPath, 'Variance');
    else
        Bad.Variance = [];
    end

    if R.FASTER_Hurst
        log_step(state, meta, R.LogFile, '[remove_bad_channels] Running FASTER Hurst detector...');
        args2 = {'elec', IdxDetect, 'measure','hurst', 'threshold', R.FASTER_HurstThreshold};
        if ~isempty(R.FASTER_RefChan), args2 = [args2, {'refchan', R.FASTER_RefChan}]; end
        if ~isempty(R.FASTER_Bandpass), args2 = [args2, {'bandpass', R.FASTER_Bandpass}]; end
        [~, idx] = FASTER_rejchan(EEG, args2{:});
        if ~isempty(R.FASTER_RefChan), idx = setdiff(idx, R.FASTER_RefChan); end
        Bad.Hurst = idx(:)';
        used{end+1} = 'FASTER_Hurst';
        logplot_badchannels(EEG, Bad.Hurst, R.LogPath, 'Hurst');
    else
        Bad.Hurst = [];
    end

    if R.CleanRaw_Flatline
        log_step(state, meta, R.LogFile, '[remove_bad_channels] Running CleanRaw Flatline detector...');
        idx = cleanraw_rejchan(EEG, 'elec', IdxDetect, 'measure','flatline', 'threshold', R.Flatline_Sec, 'highpass', R.CleanDrift_Band);
        Bad.Flatline = idx(:)';
        used{end+1} = 'Flatline';
        logplot_badchannels(EEG, Bad.Flatline, R.LogPath, 'Flatline');
    else
        Bad.Flatline = [];
    end

    if R.CleanRaw_Noise
        log_step(state, meta, R.LogFile, '[remove_bad_channels] Running CleanRaw Noise detector...');
        idx = cleanraw_rejchan(EEG, 'elec', IdxDetect, 'measure','CleanChan', 'chancorr_crit', R.CleanChan_Corr, 'line_crit', R.CleanChan_Line, 'maxbadtime', R.CleanChan_MaxBad, 'num_samples', R.CleanChan_NSamp, 'highpass', R.CleanDrift_Band);
        Bad.CleanChan = idx(:)';
        used{end+1} = 'CleanChan';
        logplot_badchannels(EEG, Bad.CleanChan, R.LogPath, 'CleanChan');
    else
        Bad.CleanChan = [];
    end

    Bad.Known = unique(KnownBadIdx(:)','stable');

    fields = {'Kurt','Spec','Prob','MeanCorr','Variance','Hurst','Flatline','CleanChan','Known'};
    allBad = [];
    summary = struct();
    for k = 1:numel(fields)
        f = fields{k};
        if ~isfield(Bad,f) || isempty(Bad.(f)), Bad.(f) = []; end
        summary.(f) = numel(Bad.(f));
        allBad = [allBad, Bad.(f)];
    end
    Bad.all = unique(allBad, 'stable');
    summary.Total = numel(Bad.all);

    log_step(state, meta, R.LogFile, sprintf('[remove_bad_channels] Total bad channels identified: %d', summary.Total));
    logreport_badchannels(Bad, R.LogFile);

    switch lower(R.Action)
        case 'remove'
            if ~isempty(Bad.all)
                log_step(state, meta, R.LogFile, sprintf('[remove_bad_channels] Removing %d bad channels...', summary.Total));
                EEG = pop_select(EEG, 'rmchannel', Bad.all);
                EEG = eeg_checkset(EEG);
                log_step(state, meta, R.LogFile, '[remove_bad_channels] Bad channels removed successfully.');
            else
                log_step(state, meta, R.LogFile, '[remove_bad_channels] No bad channels to remove.');
            end
        case 'flag'
            log_step(state, meta, R.LogFile, sprintf('[remove_bad_channels] Flagging %d bad channels...', summary.Total));
            mask = true(1, EEG.nbchan);
            mask(Bad.all(Bad.all>=1 & Bad.all<=EEG.nbchan)) = false;
            EEG.etc.clean_channel_mask = mask(:)';
            log_step(state, meta, R.LogFile, '[remove_bad_channels] Bad channels flagged successfully.');
    end

    out.Bad = Bad;
    out.summary = summary;
    out.detectors_used = used;
    out.IdxDetect = IdxDetect;

    if ~isfield(EEG.etc, 'EEGdojo'), EEG.etc.EEGdojo = struct(); end
    EEG.etc.EEGdojo.BadChanIdx = Bad.all;
    EEG.etc.EEGdojo.BadChanLabel = idx2chans(EEG, Bad.all);
    EEG.etc.EEGdojo.BadChanSummary = summary;
    EEG.etc.EEGdojo.BadDetectorsUsed = used;

    state.EEG = EEG;
    state = state_update_history(state, op, state_strip_eeg_param(R), 'success', out);
end
