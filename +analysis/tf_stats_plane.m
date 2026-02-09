function state = tf_stats_plane(state, args, ~)
%TF_STATS_PLANE Cluster-permutation/TFCE-like stats on TF plane.
%
% Args:
%   name (char)          result name
%   contrast (char)      contrast name in state.Results.Contrasts
%   roi (char)           ROI name (optional). If empty, uses all channels.
%   design (char)        'onesample'|'paired'|'two-sample' (default inferred)
%   alpha (double)       default 0.05
%   n_perm (int)         default 200
%   method (char)        'cluster' (default) | 'none'
%   tail (char)          'two' (default) | 'pos' | 'neg'

    if nargin < 2, args = struct(); end
    if ~isfield(args, 'alpha'), args.alpha = 0.05; end
    if ~isfield(args, 'n_perm'), args.n_perm = 200; end
    if ~isfield(args, 'method'), args.method = 'cluster'; end
    if ~isfield(args, 'tail'), args.tail = 'two'; end
    if ~isfield(args, 'roi'), args.roi = ''; end

    state_check(state, 'Contrasts');
    cname = args.contrast;
    if ~isfield(state.Results.Contrasts, cname)
        error('Contrast "%s" not found.', cname);
    end
    C = state.Results.Contrasts.(cname);

    % Infer design
    design = '';
    if isfield(args, 'design') && ~isempty(args.design)
        design = args.design;
    elseif isfield(C, 'maps')
        design = 'onesample';
    elseif isfield(C, 'pos_maps') && isfield(C, 'neg_maps')
        design = 'two-sample';
    else
        error('Cannot infer design for contrast "%s".', cname);
    end

    % Build data arrays: [f x t x subj] (ROI-averaged)
    [X1, X2, freqs, times] = build_tf_arrays(state, C, design, args.roi);

    if ~exist('ttest', 'file')
        error('Statistics Toolbox required for t-tests.');
    end

    switch design
        case 'onesample'
            [tmap, pmap] = tmap_onesample(X1);
        case 'paired'
            [tmap, pmap] = tmap_paired(X1, X2);
        case 'two-sample'
            [tmap, pmap] = tmap_twosample(X1, X2);
        otherwise
            error('Unknown design "%s".', design);
    end

    mask = [];
    clusters = [];
    if strcmpi(args.method, 'cluster')
        mask = cluster_perm_mask(X1, X2, design, tmap, args.alpha, args.n_perm, args.tail);
        clusters = struct('method','cluster','alpha',args.alpha,'n_perm',args.n_perm);
    end

    S = struct();
    S.design = design;
    S.method = args.method;
    S.alpha = args.alpha;
    S.n_perm = args.n_perm;
    S.t = tmap;
    S.p = pmap;
    S.mask = mask;
    S.freqs = freqs;
    S.times = times;
    S.roi = args.roi;
    S.contrast = cname;
    S.clusters = clusters;

    state.Results.Stats.TF.(args.name) = S;
    fprintf('TF stats "%s" computed (design=%s).\n', args.name, design);
end

% ---------------- helpers ----------------

function [X1, X2, freqs, times] = build_tf_arrays(state, C, design, roi)
    if ~isempty(roi)
        [ch_idx, ~] = state_get_indices(state, roi);
    else
        ch_idx = [];
    end

    if isfield(C, 'freqs'), freqs = C.freqs; else, freqs = state.Dataset.data.meta.freqs; end
    if isfield(C, 'times'), times = C.times; else, times = state.Dataset.data.meta.times; end

    switch design
        case 'onesample'
            maps = C.maps; % [chan f t subj]
            X1 = reduce_roi(maps, ch_idx);
            X2 = [];
        case 'paired'
            X1 = reduce_roi(C.pos_maps, ch_idx);
            X2 = reduce_roi(C.neg_maps, ch_idx);
        case 'two-sample'
            X1 = reduce_roi(C.pos_maps, ch_idx);
            X2 = reduce_roi(C.neg_maps, ch_idx);
        otherwise
            error('Unknown design "%s".', design);
    end
end

function X = reduce_roi(maps, ch_idx)
    if isempty(ch_idx)
        X = squeeze(mean(maps, 1)); % [f x t x subj]
    else
        X = squeeze(mean(maps(ch_idx, :, :, :), 1)); % [f x t x subj]
    end
end

function [tmap, pmap] = tmap_onesample(X)
    [F,T,N] = size(X);
    tmap = zeros(F,T); pmap = ones(F,T);
    for f = 1:F
        for t = 1:T
            [~, p, ~, stats] = ttest(squeeze(X(f,t,:)));
            tmap(f,t) = stats.tstat;
            pmap(f,t) = p;
        end
    end
end

function [tmap, pmap] = tmap_paired(X1, X2)
    [F,T,~] = size(X1);
    tmap = zeros(F,T); pmap = ones(F,T);
    for f = 1:F
        for t = 1:T
            [~, p, ~, stats] = ttest(squeeze(X1(f,t,:)), squeeze(X2(f,t,:)));
            tmap(f,t) = stats.tstat;
            pmap(f,t) = p;
        end
    end
end

function [tmap, pmap] = tmap_twosample(X1, X2)
    [F,T,~] = size(X1);
    tmap = zeros(F,T); pmap = ones(F,T);
    for f = 1:F
        for t = 1:T
            [~, p, ~, stats] = ttest2(squeeze(X1(f,t,:)), squeeze(X2(f,t,:)));
            tmap(f,t) = stats.tstat;
            pmap(f,t) = p;
        end
    end
end

function mask = cluster_perm_mask(X1, X2, design, tmap_obs, alpha, n_perm, tail)
    % threshold using t critical
    switch design
        case 'onesample'
            df = size(X1,3) - 1;
        case 'paired'
            df = size(X1,3) - 1;
        case 'two-sample'
            df = size(X1,3) + size(X2,3) - 2;
    end
    if strcmpi(tail, 'two')
        tcrit = tinv(1 - alpha/2, df);
        thr = @(T) abs(T) >= tcrit;
    elseif strcmpi(tail, 'pos')
        tcrit = tinv(1 - alpha, df);
        thr = @(T) T >= tcrit;
    else
        tcrit = tinv(1 - alpha, df);
        thr = @(T) T <= -tcrit;
    end

    obs_mask = thr(tmap_obs);
    obs_clusters = find_clusters(tmap_obs, obs_mask);
    if isempty(obs_clusters)
        mask = false(size(tmap_obs));
        return;
    end

    max_null = zeros(n_perm,1);
    for p = 1:n_perm
        [Xp, Xn] = permute_samples(X1, X2, design);
        switch design
            case 'onesample'
                tmap = tmap_onesample(Xp);
            case 'paired'
                tmap = tmap_paired(Xp, Xn);
            case 'two-sample'
                tmap = tmap_twosample(Xp, Xn);
        end
        m = thr(tmap);
        cl = find_clusters(tmap, m);
        if isempty(cl)
            max_null(p) = 0;
        else
            max_null(p) = max([cl.mass]);
        end
    end

    mask = false(size(tmap_obs));
    for i = 1:numel(obs_clusters)
        pval = mean(max_null >= obs_clusters(i).mass);
        if pval < alpha
            mask(obs_clusters(i).indices) = true;
        end
    end
end

function [Xp, Xn] = permute_samples(X1, X2, design)
    switch design
        case 'onesample'
            sgn = (rand(1, size(X1,3)) > 0.5) * 2 - 1;
            Xp = X1 .* reshape(sgn, [1 1 numel(sgn)]);
            Xn = [];
        case 'paired'
            flip = rand(1, size(X1,3)) > 0.5;
            Xp = X1;
            Xn = X2;
            Xp(:,:,flip) = X2(:,:,flip);
            Xn(:,:,flip) = X1(:,:,flip);
        case 'two-sample'
            Xp = X1;
            Xn = X2;
            allX = cat(3, X1, X2);
            n1 = size(X1,3);
            idx = randperm(size(allX,3));
            Xp = allX(:,:,idx(1:n1));
            Xn = allX(:,:,idx(n1+1:end));
    end
end

function clusters = find_clusters(tmap, mask)
    clusters = struct('indices', {}, 'mass', {});
    if ~any(mask(:)), return; end
    [F,T] = size(mask);
    visited = false(F,T);
    dirs = [1 0; -1 0; 0 1; 0 -1];
    for f = 1:F
        for t = 1:T
            if mask(f,t) && ~visited(f,t)
                q = [f t];
                visited(f,t) = true;
                inds = sub2ind([F T], f, t);
                while ~isempty(q)
                    cur = q(1,:); q(1,:) = [];
                    for d = 1:size(dirs,1)
                        nf = cur(1) + dirs(d,1);
                        nt = cur(2) + dirs(d,2);
                        if nf>=1 && nf<=F && nt>=1 && nt<=T && mask(nf,nt) && ~visited(nf,nt)
                            visited(nf,nt) = true;
                            q(end+1,:) = [nf nt]; %#ok<AGROW>
                            inds(end+1) = sub2ind([F T], nf, nt); %#ok<AGROW>
                        end
                    end
                end
                mass = sum(abs(tmap(inds)));
                clusters(end+1).indices = inds; %#ok<AGROW>
                clusters(end).mass = mass;
            end
        end
    end
end
