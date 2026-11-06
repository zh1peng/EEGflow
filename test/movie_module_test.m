function movie_module_test()
%MOVIE_MODULE_TEST Numerical and data-flow checks on synthetic EEG.
% Requires EEGLAB (including clean_rawdata) on the path. Tensor Toolbox is
% optional; its CP reconstruction check is run when installed.

    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root, fullfile(root, 'utils'));
    oldVisible = get(groot, 'defaultFigureVisible');
    set(groot, 'defaultFigureVisible', 'off');
    cleanup = onCleanup(@() set(groot, 'defaultFigureVisible', oldVisible)); %#ok<NASGU>
    rng(41);

    % Regression for eegrej's boundary adjustment over multiple removed spans.
    events = struct('type', {'before','drop1','middle','drop2','after'}, ...
        'latency', {2,4,8,11,18});
    [kept, duration, events, boundaries] = eegrej(1:20, [3 5;10 12], 20, events);
    assert(isequal(kept, [1:2,6:9,13:20]));
    assert(duration == 14 && isequal(boundaries(:), [2.5;6.5]));
    assert(~any(ismember({events.type}, {'drop1','drop2'})));
    assert(events(strcmp({events.type},'middle')).latency == 5);
    assert(events(strcmp({events.type},'after')).latency == 12);

    fs = 128;
    n = fs * 64;
    firstSample = 129;
    lastSample = n-128;
    segmentLength = lastSample-firstSample+1;
    t = (0:n-1)/fs;
    shared = [sin(2*pi*8*t); cos(2*pi*13*t)];
    mixing = randn(6, 2);
    outDir = fullfile(root, 'test', 'out', 'movie');
    if ~isfolder(outDir), mkdir(outDir); end
    files = cell(1, 4);
    for s = 1:4
        EEG = eeg_emptyset;
        EEG.data = mixing*shared + 0.5*randn(6,n) + ...
            (3:8)'*sin(2*pi*0.25*t + s/4);
        EEG.srate = fs;
        EEG.nbchan = 6;
        EEG.pnts = n;
        EEG.trials = 1;
        EEG.xmin = 0;
        EEG.xmax = (n-1)/fs;
        for c = 1:6
            EEG.chanlocs(c).labels = sprintf('E%d', c);
            EEG.chanlocs(c).theta = (c-1)*60;
            EEG.chanlocs(c).radius = 0.45;
        end
        EEG.chanlocs = convertlocs(EEG.chanlocs, 'topo2all');
        EEG.urchanlocs = EEG.chanlocs;
        EEG.etc.EEGdojo.BadChanSummary.Total = 0;
        EEG.event = struct('type', {'before','start','stim','stop','after'}, ...
            'latency', {64,firstSample,n/2,lastSample,n-64});
        EEG = eeg_checkset(EEG);
        files{s} = fullfile(outDir, sprintf('sub_%02d.set', s));
        pop_saveset(EEG, 'filename', sprintf('sub_%02d.set', s), ...
            'filepath', outDir, 'savemode', 'onefile');
    end

    % The explicit QC filter must equal filtering a copy in the caller.
    original = EEG;
    EEGqc = pop_eegfiltnew(EEG, 'locutoff', 1);
    EEGqc = eeg_checkset(EEGqc);
    expectedQC = calculate_data_quality(EEGqc);
    actualQC = calculate_data_quality(EEG, 'qc_locutoff', 1);
    assert(isequaln(actualQC, expectedQC));
    assert(isequaln(EEG, original), 'QC changed its input EEG.');
    rawQC = calculate_data_quality(EEG);
    disabledQC = calculate_data_quality(EEG, 'qc_locutoff', 0);
    assert(isequaln(rawQC, disabledQC));
    assert(actualQC.global_field_power_mean < rawQC.global_field_power_mean);

    % Interior crop: retained samples and event coordinates must be exact.
    cropped = prep.crop_by_markers(struct('EEG',EEG), ...
        struct('StartMarker','start','EndMarker','stop'));
    assert(cropped.EEG.pnts == segmentLength);
    assert(isequal(cropped.EEG.data, EEG.data(:,firstSample:lastSample)));
    ev = cropped.EEG.event;
    assert(~any(ismember({ev.type}, {'before','after'})));
    assert(ev(strcmp({ev.type},'start')).latency == 1);
    assert(ev(strcmp({ev.type},'stim')).latency == n/2-firstSample+1);
    assert(ev(strcmp({ev.type},'stop')).latency == segmentLength);

    % QC uses the full recording's 1 Hz copy, while analysis arrays contain
    % only the unfiltered interior segment when locutoff is empty.
    data = movie.collect_segments('setFile', files, 'StartMarker', 'start', ...
        'EndMarker', 'stop', 'check_quality', true, 'run_tag', 'test');
    assert(isequal(data.sub_04.data, double(EEG.data(:,firstSample:lastSample))));
    assert(isequaln(data.sub_04.quality_info, expectedQC));
    assert(data.sub_04.crop_info.start_sample == firstSample);
    assert(data.sub_04.crop_info.end_sample == lastSample);
    aligned = movie.collect_segments('setFile', files(1), 'StartMarker', 'start', ...
        'EndMarker', 'stop', 'expected_length', segmentLength-17, 'check_quality', true);
    assert(size(aligned.sub_01.data,2) == segmentLength-17);
    assert(aligned.sub_01.quality_info.data_point_count == n);

    % Optional transforms must reach the returned, cropped analysis arrays.
    envelope = movie.collect_segments('setFile', files(4), 'StartMarker', 'start', ...
        'EndMarker', 'stop', 'hilbert_env', true);
    expectedEnvelope = abs(hilbert(data.sub_04.data.')).';
    assert(max(abs(envelope.sub_04.data-expectedEnvelope),[],'all') < 1e-10);
    if exist('CSD','file') && exist('GetGH','file')
        montage.lab = {data.meta.chanlocs.labels};
        montage.theta = [data.meta.chanlocs.sph_theta];
        montage.phi = [data.meta.chanlocs.sph_phi];
        [G,H] = GetGH(montage,4);
        expectedCSD = CSD(data.sub_04.data,G,H,1e-5,10);
        csdData = movie.collect_segments('setFile', files(4), 'StartMarker', 'start', ...
            'EndMarker', 'stop', 'csd', true);
        assert(max(abs(csdData.sub_04.data-expectedCSD),[],'all') < 1e-10);
        resampled = interp1(1:segmentLength,data.sub_04.data.', ...
            linspace(1,segmentLength,segmentLength-17),'pchip').';
        expectedBoth = abs(hilbert(CSD(resampled,G,H,1e-5,10).')).';
        both = movie.collect_segments('setFile', files(4), 'StartMarker', 'start', ...
            'EndMarker', 'stop', 'expected_length', segmentLength-17, ...
            'csd', true, 'hilbert_env', true);
        assert(max(abs(both.sub_04.data-expectedBoth),[],'all') < 1e-10);
    else
        fprintf('CSD checks not run: CSD Toolbox is not on the path.\n');
    end

    % The file QC entry point uses exactly the same default 1 Hz metrics.
    [q, flags] = movie.qc_files('study_path', outDir, ...
        'searchstring', '^sub_04\.set$', 'parallel', false, ...
        'metrics_to_analyze', {'percent_retained_by_windows'});
    assert(q.percent_retained_by_windows == expectedQC.percent_retained_by_windows);
    assert(height(flags) == 1);

    % Explicit thresholds filter whole subjects; flag-only preserves arrays.
    data.meta.data_quality.percent_retained_by_windows = [97; 60; 92; NaN];
    qcArgs = {'metrics_to_analyze', {'percent_retained_by_windows'}, ...
        'thresholds', struct('percent_retained_by_windows',85)};
    flagged = movie.qc_filter(data, qcArgs{:}, 'filter_data', false);
    filtered = movie.qc_filter(data, qcArgs{:});
    assert(isequal(flagged.meta.auto_qc.include_auto, logical([1;0;1;1])));
    assert(isequal(flagged.sub_02.data, data.sub_02.data));
    assert(~isfield(filtered,'sub_02') && isfield(filtered,'sub_04'));
    assert(height(filtered.meta.data_quality_after_qc) == 3);
    % These amplitude metrics use upper bounds, for explicit and MAD cutoffs.
    amplitudeData = data;
    metrics = {'amplitude_spread_1k','amplitude_spread_global','global_field_power_mean'};
    thresholds = struct();
    for i = 1:numel(metrics)
        amplitudeData.meta.data_quality.(metrics{i}) = [1;2;100;NaN];
        thresholds.(metrics{i}) = 2;
    end
    explicit = movie.qc_filter(amplitudeData, 'metrics_to_analyze', metrics, ...
        'thresholds', thresholds, 'filter_data', false);
    automatic = movie.qc_filter(amplitudeData, 'metrics_to_analyze', metrics, ...
        'filter_data', false);
    for i = 1:numel(metrics)
        assert(isequal(explicit.meta.auto_qc.(metrics{i}),logical([1;1;0;1])));
        assert(isequal(automatic.meta.auto_qc.(metrics{i}),logical([1;1;0;1])));
    end
    [valid, keep, target] = movie.qc_lengths([1000;1001;999;1200],100,0.1);
    assert(isequal(valid, logical([1;1;1;0])) && isequal(keep,[1;2;3]));
    assert(target == 1000.5);

    % QC tolerance is in EEG samples even when TFR returns fewer time bins.
    tfr = movie.collect_segments('setFile', files(1), 'StartMarker', 'start', ...
        'EndMarker', 'stop', 'expected_length', 4096, 'tfr', true, ...
        'chan_include', {'E1','E2'}, 'tfr_freqs', [6 16]);
    assert(size(tfr.sub_01.data,3) ~= 4096);
    lengthCfg.steps = struct('op','qc_lengths','args',struct());
    lengthPipe = movie.build_pipeline(lengthCfg,'State',struct('movie',struct('data',tfr)));
    [lengthState,lengthReport] = lengthPipe.run();
    assert(lengthReport.ok && lengthState.movie.qc.lengths.target_len == 4096);

    % Streaming and stacked CorrCA should yield the same ISC with identical
    % preprocessing. Align arbitrary eigenvector signs before comparing Y.
    [W, isc, Y, A] = movie.run_corrca(data, 'shrinkage', 0.1);
    [Ws, iscs, Ys] = movie.run_corrca_stream('setFile', files, ...
        'StartMarker', 'start', 'EndMarker', 'stop', 'shrinkage', 0.1, ...
        'parallel', false, 'verbose', false);
    signs = sign(sum(W.*Ws,1));
    assert(max(abs(isc-iscs)) < 1e-8);
    assert(max(abs(W-Ws.*signs),[],'all') < 1e-7);
    assert(max(abs(Y-double(Ys).*reshape(signs,1,[],1)),[],'all') < 1e-5);
    assert(isequal(size(A),[6,6]));

    % The fixed-projection pipeline must expose the direct function's p-values.
    [Wf,iscf,Yf,Af,pf] = movie.run_corrca(data, 'fixed', eye(6));
    fixedCfg.steps = struct('id','fixed_corrca','op','run_corrca', ...
        'args',struct('fixed',eye(6)));
    fixedPipe = movie.build_pipeline(fixedCfg,'State',struct('movie',struct('data',data)));
    [fixedState,fixedReport] = fixedPipe.run();
    assert(fixedReport.ok);
    assert(isequaln(fixedState.movie.corrca, ...
        struct('W',Wf,'ISC',iscf,'Y',Yf,'A',Af,'p',pf)));

    assert(size(Y,1) == segmentLength);
    signals = reshape(Y(:,1,:),segmentLength,4);
    [iscSubject, ~, pairs] = movie.compute_isc(signals, 'pairwise', true, 'fisherZ', false);
    assert(max(abs(pairs-corr(signals)),[],'all') < 1e-10);
    assert(all(isfinite(iscSubject)));
    [tr, trmeta, trpairs] = movie.compute_isc(signals, 'timeResolved', true, ...
        'winLength', 129, 'overlap', 0.5, 'pairwise', true);
    assert(isequal(size(tr),[4,numel(trmeta.centerIdx)]));
    assert(size(trpairs,3) == size(tr,2));
    inferred = movie.test_isc(signals, 'nPerm', 19, 'parallel', false, ...
        'randomSeed', 7, 'verbose', false);
    assert(isequaln(inferred.obs.ISC, iscSubject));
    movie.plot_isc_test(inferred);

    % Exercise the shipped JSON workflow, including collection and QC adapters.
    cfg = flow.load_cfg(fullfile(root,'config_template','movie_config.json'));
    cfg.steps(1).args.study_path = outDir;
    cfg.steps(1).args.subject_parser = '(?<sub>sub_\d+)';
    cfg.steps(1).args.StartMarker = 'start';
    cfg.steps(1).args.EndMarker = 'stop';
    cfg.steps(4).args.fisherZ = false;
    cfg.steps(5).args.nPerm = 19;
    cfg.steps(5).args.randomSeed = 7;
    cfg.steps(5).args.verbose = false;
    pipe = movie.build_pipeline(cfg);
    [state, report] = pipe.run();
    assert(report.ok);
    assert(~isfield(state.movie.corrca,'p'));
    assert(isequal(state.movie.data.sub_04.data, data.sub_04.data));
    assert(max(abs(state.movie.isc.pairwise-pairs),[],'all') < 1e-10);
    movie.plot_isc_timecourse(Y,A,data.meta.chanlocs,'Fs',fs, ...
        'ISCArgs',{'timeResolved',true,'winLength',129,'overlap',0.5});
    movie.plot_isc_band_summary({Y,Y},'CompList',1:2, ...
        'BandLabels',{'band1','band2'});
    movie.plot_isc_topographies({A,A},data.meta.chanlocs,'CompList',1:2);

    % Similarities, Mantel, and MRQAP: known relationships and dyad regression.
    scores = [1;2;4;6;9;13];
    S = movie.build_similarity_univariate(scores, 'uniModel','absdiff', 'rank',false);
    assert(max(abs(S-(1-abs(scores-scores')/12)),[],'all') < 1e-12);
    features = [scores, scores.^2, sin(scores)];
    [Sm, smeta] = movie.build_similarity_multivariate(features, 'method','embedding-corr');
    assert(max(abs(Sm-corr(features')),[],'all') < 1e-10);
    assert(smeta.N == numel(scores));
    mantel = movie.rsa_mantel(S,S,'nPerm',19,'seed',8);
    assert(abs(mantel.r-1) < 1e-12 && mantel.p >= 1/20);
    noise = randn(6); noise = (noise+noise')/2;
    neural = 0.3 + 0.7*S + 0.05*noise;
    stats = movie.rsa_mrqap(neural,S,[],'nPerm',19,'seed',8,'direction','similarity');
    mask = tril(true(6),-1);
    beta = [ones(nnz(mask),1),S(mask)] \ neural(mask);
    assert(max(abs(stats.beta-beta)) < 1e-10);
    movie.summarize_rsa_mrqap(stats);
    movie.plot_similarity(S);
    embeddingSimilarity = exp(-squareform(pdist(randn(6,3))).^2);
    movie.plot_similarity_embedding(embeddingSimilarity,'method','mds');

    % Preserve event-like feature holds and continuous interpolation.
    ts = (0:3)'; tt = (0:0.5:3)';
    held = movie.resample_feature(ts,[0;1;0;1],tt,'hold');
    assert(isequal(held,[0;0;1;1;0;0;1]));
    interpolated = movie.resample_feature(ts,2*ts,tt,'interp');
    assert(max(abs(interpolated-2*tt)) < 1e-12);
    csv = table(ts,[0;1;0;1],2*ts,'VariableNames',{'seconds','event','feature'});
    csvPath = fullfile(outDir,'features.csv'); writetable(csv,csvPath);
    [F,names,times] = movie.resample_features_csv(csvPath,'tTarget',tt, ...
        'HoldVars',{'event'},'ContMode','interp');
    assert(isequal(times,tt) && isequal(F(:,strcmp(names,'event')),held));
    assert(max(abs(F(:,strcmp(names,'feature'))-2*tt)) < 1e-12);

    if exist('cp_als','file')
        rankOne.meta = data.meta;
        wave = sin((1:80)/9);
        for s=1:4, rankOne.(sprintf('sub_%02d',s)).data = (1:6)'*wave*s; end
        cp = movie.run_cp(rankOne,'Rank',1,'ZscoreAcrossTime',false,'Plot',false);
        residual = norm(cp.T-full(cp.cp))/norm(cp.T);
        assert(residual < 1e-6);
        movie.plot_cp(cp);

        % Force a negative temporal peak in the raw CP result, then verify
        % that sign normalization preserves the weighted reconstruction.
        wave = [ones(1,79),-2];
        for s=1:4, rankOne.(sprintf('sub_%02d',s)).data = (1:6)'*wave*s; end
        rawTensor = tensor(cat(3,rankOne.sub_01.data,rankOne.sub_02.data, ...
            rankOne.sub_03.data,rankOne.sub_04.data));
        rng(7);
        referenceCP = cp_als(rawTensor,1,'printitn',0,'tol',1e-6,'maxiters',500);
        [~,peak] = max(abs(referenceCP.U{2}));
        assert(referenceCP.U{2}(peak) < 0, 'Fixture must exercise a sign flip.');
        rng(7);
        corrected = movie.run_cp(rankOne,'Rank',1,'ZscoreAcrossTime',false,'Plot',false);
        assert(corrected.B(peak) > 0);
        reconstructed = full(ktensor(corrected.cp.lambda, ...
            {corrected.A,corrected.B,corrected.C}));
        assert(norm(reconstructed-full(referenceCP))/norm(rawTensor) < 1e-10);
        assert(isequal(corrected.cp.U,{corrected.A;corrected.B;corrected.C}));
        assert(norm(corrected.T-full(corrected.cp))/norm(corrected.T) < 1e-6);
    else
        fprintf('CP reconstruction not run: Tensor Toolbox is not on the path.\n');
    end
    close all;
    fprintf('movie_module_test passed. Synthetic files: %s\n',outDir);
end
