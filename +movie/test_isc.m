function out = test_isc(Y, varargin)
% TEST_ISC  Permutation test for ISC (static or time-resolved) on CorrCA-projected Y.
%
% USAGE
%   out = test_isc(Y, 'timeResolved', true, 'winLength', 30*Fs, ...
%                      'shuffle','circular', 'nPerm',1000, 'alpha',0.05, ...
%                      'verbose', true, 'randomSeed',123);
%
% INPUT
%   Y : [T x N]   (time x subjects) single CorrCA component/band time series per subject.
%
% OPTIONS (name-value)
%   % Core ISC computation (passed to movie.compute_isc)
%   'timeResolved' (false)    : If true, compute sliding-window ISC.
%   'winLength'    ([])       : Window length in samples. Required when timeResolved=true.
%   'edgeMode'     ('replicate') : 'replicate' | 'reflect' | 'shrink'.
%   'pairMetric'   ('corr')   : 'corr' | 'cov'.
%   'fisherZ'      (true)     : Fisher-z handling when pairMetric='corr'.
%
%   % Permutations & surrogates
%   'nPerm'        (1000)     : Number of permutations.
%   'alpha'        (0.05)     : Family-wise alpha (used for thresholds).
%   'shuffle'      ('circular'): 'circular' | 'phase' | 'block'.
%   'minShift'     (250)      : Min circular shift (samples).
%   'blockLen'     (250)      : Block length for 'block' shuffle.
%   'randomSeed'   ([])       : Base RNG seed for reproducibility (empty => random).
%
%   % Inference parameters
%   'clusterZ'     (1.64)     : Cluster-forming z-threshold (one-sided) for cluster mass.
%   'tfceE'        (0.5)      : TFCE extent exponent E.
%   'tfceH'        (2.0)      : TFCE height exponent H.
%   'tfceDh'       (0.1)      : TFCE threshold step (in z units).
%
%   % Runtime / logging
%   'parallel'     (true)     : Try parallel pool; fallback to serial on failure.
%   'verbose'      (true)     : Print header + 5% progress + timing.
%
% OUTPUT (struct)
%   .meta                 : Settings and compute_isc metadata.
%   .obs.ISC              : [N x 1] or [N x T] per-subject LOSO ISC.
%   .obs.group            : [1 x 1] or [1 x T] group ISC (subject-aggregated).
%   .null.group           : [nPerm x 1] or [nPerm x T] group null (single precision).
%   .null.mean_t          : [1 x T] permutation mean per time (double).
%   .null.sd_t            : [1 x T] permutation sd per time (double).
%   .inference.pointwise  : struct with fields .p (1xT or scalar), .thr (1xT), .sigMask
%   .inference.maxT       : struct with fields .z_obs, .critZ, .p_corr (1xT or scalar), .sigMask, .maxZ
%   .inference.cluster    : struct with fields .z_obs, .z0, .obsClusters[Kx3], .pFWER_top, .sigMaskFWER, .maxNullMass
%   .inference.tfce       : struct with fields .tfce_obs, .critTFCE, .p_corr, .sigMask, .maxTFCE
%   .diagnostics          : Summary stats of obs/null.
%
% NOTES
%   • The four inference modes are computed together; you can plot any later without re-running.
%   • Studentization uses null mean/sd per time; maxT/cluster/TFCE are computed on z-statistics.
%   • Cluster mass: cluster "mass" = sum(z - z0) across each supra-threshold run; FWER via max cluster mass.
%   • TFCE: 1-D implementation over time, FWER via max TFCE per permutation.
%
% (c) 2025 – tailored for EEGdojo pipelines.

% ---------- Parse options ----------
P = inputParser;
P.addParameter('timeResolved', false, @(x)islogical(x)&&isscalar(x));
P.addParameter('winLength',    [],    @(x)isempty(x) || (isscalar(x) && x>=2 && x==floor(x)));
P.addParameter('edgeMode',     'replicate', @(s)ischar(s) || isstring(s));

P.addParameter('pairMetric',   'corr', @(s) any(strcmpi(string(s),["corr","cov"])));
P.addParameter('fisherZ',      true, @(x)islogical(x)&&isscalar(x));

P.addParameter('nPerm',        1000,  @(x)isnumeric(x)&&isscalar(x)&&x>=1);
P.addParameter('alpha',        0.05,  @(x)isnumeric(x)&&isscalar(x)&&x>0&&x<1);
P.addParameter('shuffle',      'circular', @(s) any(strcmpi(string(s),["circular","phase","block"])));
P.addParameter('minShift',     250,   @(x)isnumeric(x)&&isscalar(x)&&x>=0);
P.addParameter('blockLen',     250,   @(x)isnumeric(x)&&isscalar(x)&&x>=1);
P.addParameter('randomSeed',   [],    @(x)isempty(x) || (isscalar(x)&&isnumeric(x)));

% Inference tuning
P.addParameter('clusterZ',     1.64,  @(x)isnumeric(x)&&isscalar(x));
P.addParameter('tfceE',        0.5,   @(x)isnumeric(x)&&isscalar(x));
P.addParameter('tfceH',        2.0,   @(x)isnumeric(x)&&isscalar(x));
P.addParameter('tfceDh',       0.1,   @(x)isnumeric(x)&&isscalar(x) && x>0);

% Runtime/logging
P.addParameter('parallel',     true,  @(x)islogical(x)&&isscalar(x));
P.addParameter('verbose',      true,  @(x)islogical(x)&&isscalar(x));
P.addParameter('overlap',      [], @(x)isempty(x) || (isscalar(x) && x>=0 && x<1));
P.parse(varargin{:});
opt = P.Results;

% ---------- Basic checks ----------
if ndims(Y) ~= 2
    error('test_isc:2Donly','Y must be [T x N]. Collapse outside if needed.');
end
[T, N] = size(Y);
if ~opt.timeResolved && ~isempty(opt.winLength)
    warning('test_isc:winIgnored','winLength provided but timeResolved=false; ignoring.');
end
if opt.timeResolved && isempty(opt.winLength)
    error('test_isc:winLengthRequired','Provide winLength (samples) when timeResolved=true.');
end

% ---------- Print setup header ----------
if opt.verbose
    hdr_mode = tern(opt.timeResolved, ...
        sprintf('time-resolved (win=%d, edge=%s, metric=%s, fz=%d)', ...
                opt.winLength, char(opt.edgeMode), char(opt.pairMetric), opt.fisherZ), ...
        sprintf('static (metric=%s, fz=%d)', char(opt.pairMetric), opt.fisherZ));
    fprintf('[test_isc] T=%d, N=%d | %s | shuffle=%s | nPerm=%d | alpha=%.3g\n', ...
        T, N, hdr_mode, char(opt.shuffle), opt.nPerm, opt.alpha);
    if strcmpi(opt.shuffle,'circular')
        fprintf('[test_isc]   minShift=%d samples\n', opt.minShift);
    elseif strcmpi(opt.shuffle,'block')
        fprintf('[test_isc]   blockLen=%d samples\n', opt.blockLen);
    end
    if ~isempty(opt.randomSeed), fprintf('[test_isc]   seed=%d\n', opt.randomSeed); end
end

% ---------- Observed ISC ----------
iscArgs = {'timeResolved', opt.timeResolved, ...
           'pairMetric',   opt.pairMetric, ...
           'fisherZ',      opt.fisherZ, ...
           'edgeMode',     opt.edgeMode};
if opt.timeResolved, iscArgs = [iscArgs, {'winLength', opt.winLength, 'overlap', opt.overlap}]; end

[ISC_obs, meta_isc] = movie.compute_isc(Y, iscArgs{:});   % [N x 1] or [N x T]

% Group summary across subjects (inline; no trivial helpers)
if strcmpi(opt.pairMetric,'corr')
    ztmp = atanh(max(min(ISC_obs,0.999999),-0.999999));
    gz   = mean(ztmp, 1, 'omitnan');
    group_obs = tanh(gz);
else
    group_obs = mean(ISC_obs, 1, 'omitnan');
end
T0 = size(group_obs,2);

% ---------- Null container (single precision to save RAM) ----------
B = opt.nPerm;
if opt.timeResolved
    null_group = nan(B, T0, 'single');
else
    null_group = nan(B, 1,  'single');
end

% ---------- Ensure parallel pool (fallback to serial if it fails) ----------
useSerial = true;
if opt.parallel
    pool = gcp('nocreate');
    if isempty(pool)
        try
            parpool;
            useSerial = false;
        catch ME
            warning(ME.identifier,'[test_isc] Could not start parallel pool (%s). Falling back to serial.', ME.message);
            useSerial = true;
        end
    else
        useSerial = false;
    end
end

% ---------- Reproducible RNG plan ----------
if ~isempty(opt.randomSeed)
    baseSeed = opt.randomSeed;
else
    baseSeed = randi(1e9);
end

% ---------- Permutations (parallel if possible) ----------
t0 = tic;
if ~useSerial
    if opt.verbose
        dq = parallel.pool.DataQueue;
        afterEach(dq, @tick);
        fprintf('[test_isc] Permuting %d surrogates:\n', B);
    end
    null_local = cell(B,1);
    parfor b = 1:B
        rng(baseSeed + b);
        Yp = make_surrogates(Y, opt);
        ISC_b = movie.compute_isc(Yp, iscArgs{:});
        if strcmpi(opt.pairMetric,'corr')
            zb  = atanh(max(min(ISC_b,0.999999),-0.999999));
            gbz = mean(zb, 1, 'omitnan');
            gb  = tanh(gbz);
        else
            gb  = mean(ISC_b, 1, 'omitnan');
        end
        null_local{b} = single(gb);
        if opt.verbose, send(dq,1); end
    end
    null_group = cell2mat(null_local); % (B x T0) single
else
    if opt.verbose, fprintf('[test_isc] Permuting %d surrogates (serial):\n', B); end
    for b = 1:B
        rng(baseSeed + b);
        Yp = make_surrogates(Y, opt);
        ISC_b = movie.compute_isc(Yp, iscArgs{:});
        if strcmpi(opt.pairMetric,'corr')
            zb  = atanh(max(min(ISC_b,0.999999),-0.999999));
            gbz = mean(zb, 1, 'omitnan');
            null_group(b,:) = single(tanh(gbz));
        else
            null_group(b,:) = single(mean(ISC_b, 1, 'omitnan'));
        end
        if opt.verbose
            if b==1 || b==B || (floor(20*b/B) > floor(20*(b-1)/B))
                fprintf('%d%%\n', floor(100*b/B));
                if b==B, fprintf('\n'); end
            end
        end
    end
end
if opt.verbose
    elapsed = toc(t0);
    fprintf('[test_isc] Done permutations in %.2fs (%.1f perms/s)\n', elapsed, B/max(elapsed,eps));
end

% ---------- Descriptive pointwise (uncorrected) ----------
if ~opt.timeResolved
    p_group = (sum(null_group >= single(group_obs), 1) + 1) / (B + 1);
    thr_pt  = prctile(null_group, 100*(1-opt.alpha), 1);
    out.inference.pointwise = struct( ...
        'p',       p_group, ...
        'thr',     double(thr_pt), ...
        'sigMask', p_group < opt.alpha );
else
    p_t   = (sum(null_group >= single(group_obs), 1) + 1) ./ (B + 1);
    thr_t = prctile(null_group, 100*(1-opt.alpha), 1);
    out.inference.pointwise = struct( ...
        'p',       double(p_t), ...
        'thr',     double(thr_t), ...
        'sigMask', (double(group_obs) > double(thr_t)) );
end

% ---------- Studentization (for maxT / cluster / TFCE) ----------
mu0 = double(mean(null_group, 1, 'omitnan'));                 % 1 x T
sd0 = double(std(null_group, 0, 1, 'omitnan'));               % 1 x T
sd0 = max(sd0, eps);                                          % avoid divide-by-zero

z_obs  = (double(group_obs) - mu0) ./ sd0;                    % 1 x T
z_null = (double(null_group) - mu0) ./ sd0;                   % B x T  (double for downstream ops)

% ---------- Max-T (FWER, timepoint-level) ----------
maxZ  = max(z_null, [], 2);                                   % B x 1
critZ = prctile(maxZ, 100*(1-opt.alpha));
if ~opt.timeResolved
    p_corr = (sum(maxZ >= z_obs, 1) + 1) / (B + 1);
    sigMT  = p_corr < opt.alpha;
else
    p_corr = (sum(maxZ >= z_obs, 1) + 1) ./ (B + 1);          % 1 x T
    sigMT  = (z_obs > critZ);
end
out.inference.maxT = struct( ...
    'z_obs',   z_obs, ...
    'critZ',   critZ, ...
    'p_corr',  p_corr, ...
    'sigMask', sigMT, ...
    'maxZ',    maxZ );

% ---------- Cluster mass (FWER, cluster-level) ----------
z0 = opt.clusterZ;
if ~opt.timeResolved
    sig_pt = z_obs > z0;
    [cl_obs, mass_obs] = clusters_from_mask(sig_pt, z_obs - z0);
    % Build null of max cluster mass
    maxNullMass = zeros(B,1);
    for b = 1:B
        sig_b = z_null(b,:) > z0;                       % 1x1 logical
        [~, m_b] = clusters_from_mask(sig_b, z_null(b,:) - z0);
        if isempty(m_b)
            maxNullMass(b) = 0;
        else
            maxNullMass(b) = max(m_b);
        end
    end
    pFWER_top = 1.0; sigFWER = false(size(sig_pt));
    if ~isempty(mass_obs)
        pFWER_top = (sum(maxNullMass >= max(mass_obs)) + 1) / (B + 1);
        for k = 1:size(cl_obs,1)
            p_k = (sum(maxNullMass >= cl_obs(k,3)) + 1) / (B + 1);
            if p_k < opt.alpha
                sigFWER( cl_obs(k,1):cl_obs(k,2) ) = true;
            end
        end
    end
    out.inference.cluster = struct( ...
        'z_obs',         z_obs, ...
        'z0',            z0, ...
        'obsClusters',   cl_obs, ...
        'pFWER_top',     pFWER_top, ...
        'sigMaskFWER',   sigFWER, ...
        'maxNullMass',   maxNullMass );
else
    sig_pt = z_obs > z0;
    [cl_obs, mass_obs] = clusters_from_mask(sig_pt, z_obs - z0);
    maxNullMass = zeros(B,1);
    for b = 1:B
        sig_b = z_null(b,:) > z0;
        [~, m_b] = clusters_from_mask(sig_b, z_null(b,:) - z0);
        if isempty(m_b)
            maxNullMass(b) = 0;
        else
            maxNullMass(b) = max(m_b);
        end
    end
    pFWER_top = 1.0; sigFWER = false(size(sig_pt));
    if ~isempty(mass_obs)
        pFWER_top = (sum(maxNullMass >= max(mass_obs)) + 1) / (B + 1);
        for k = 1:size(cl_obs,1)
            p_k = (sum(maxNullMass >= cl_obs(k,3)) + 1) / (B + 1);
            if p_k < opt.alpha
                sigFWER( cl_obs(k,1):cl_obs(k,2) ) = true;
            end
        end
    end
    out.inference.cluster = struct( ...
        'z_obs',         z_obs, ...
        'z0',            z0, ...
        'obsClusters',   cl_obs, ...
        'pFWER_top',     pFWER_top, ...
        'sigMaskFWER',   sigFWER, ...
        'maxNullMass',   maxNullMass );
end

% ---------- TFCE (FWER, timepoint-level) ----------
E = opt.tfceE; H = opt.tfceH; dh = opt.tfceDh;
tfce_obs = tfce_1d(z_obs, E, H, dh);
maxTFCE  = zeros(B,1);
for b = 1:B
    tfce_b = tfce_1d(z_null(b,:), E, H, dh);
    maxTFCE(b) = max(tfce_b);
end
critTFCE = prctile(maxTFCE, 100*(1-opt.alpha));
if ~opt.timeResolved
    p_corr_tfce = (sum(maxTFCE >= tfce_obs, 1) + 1) / (B + 1);
    sig_tfce    = p_corr_tfce < opt.alpha;
else
    p_corr_tfce = (sum(maxTFCE >= tfce_obs, 1) + 1) ./ (B + 1); % 1xT vectorized compare
    sig_tfce    = tfce_obs > critTFCE;
end
out.inference.tfce = struct( ...
    'tfce_obs', tfce_obs, ...
    'critTFCE', critTFCE, ...
    'p_corr',   p_corr_tfce, ...
    'sigMask',  sig_tfce, ...
    'maxTFCE',  maxTFCE );

% ---------- Package ----------
out.meta = struct( ...
    'T', T, 'N', N, ...
    'timeResolved', logical(opt.timeResolved), ...
    'winLength',    tern(opt.timeResolved, opt.winLength, []), ...
    'edgeMode',     char(opt.edgeMode), ...
    'pairMetric',   char(opt.pairMetric), ...
    'fisherZ',      logical(opt.fisherZ), ...
    'nPerm',        opt.nPerm, ...
    'alpha',        opt.alpha, ...
    'shuffle',      char(opt.shuffle), ...
    'minShift',     opt.minShift, ...
    'blockLen',     opt.blockLen, ...
    'randomSeed',   opt.randomSeed, ...
    'clusterZ',     opt.clusterZ, ...
    'tfceE',        opt.tfceE, ...
    'tfceH',        opt.tfceH, ...
    'tfceDh',       opt.tfceDh );

out.obs.ISC       = ISC_obs;
out.obs.group     = group_obs;
out.null.group    = null_group;           % single precision (B x T0)
out.null.mean_t   = mu0;
out.null.sd_t     = sd0;

% Diagnostics
if ~opt.timeResolved
    out.diagnostics = struct('obs_group',group_obs, ...
                             'null_mean',mean(null_group,'all','omitnan'), ...
                             'null_std', std(null_group,0,'all','omitnan'), ...
                             'null_p95', prctile(null_group,95,'all'));
else
    out.diagnostics = struct('obs_group_mean', mean(group_obs,'omitnan'), ...
                             'null_mean_t',    mu0, ...
                             'null_p95_t',     double(prctile(null_group,95,1)));
end

% ===== nested callback for parallel progress =====
    function tick(~)
        persistent completed lastPctPrinted
        if isempty(completed), completed = 0; lastPctPrinted = -1; end
        completed = completed + 1;
        pct = floor(100 * completed / B);
        if pct >= lastPctPrinted + 5 || pct==100 || pct==1
            fprintf('%d%%\n', pct);
            lastPctPrinted = pct;
            if pct==100, fprintf('\n'); end
        end
    end
end % test_isc


% ==================== Helper functions (documented) ====================

function Yperm = make_surrogates(Y, opt)
% MAKE_SURROGATES  Build subject-wise surrogate time series according to 'shuffle' mode.
%   'circular' : independent random circular shift per subject; preserves spectrum/ACF.
%   'phase'    : phase-randomized surrogate per subject; preserves power spectrum exactly.
%   'block'    : permute contiguous blocks of length 'blockLen'; preserves local structure.
[T, N] = size(Y);
Yperm = zeros(T, N, 'like', Y);
switch lower(string(opt.shuffle))
    case "circular"
        for s = 1:N
            if opt.minShift == 0
                off = randi([0, T-1],1,1);
            else
                off = randi([opt.minShift, T-opt.minShift],1,1);
            end
            Yperm(:,s) = circshift(Y(:,s), off, 1);
        end
    case "phase"
        for s = 1:N
            Yperm(:,s) = phase_randomize(Y(:,s));
        end
    case "block"
        for s = 1:N
            Yperm(:,s) = block_shuffle(Y(:,s), opt.blockLen);
        end
    otherwise
        error('make_surrogates:shuffle','Unknown shuffle method: %s', string(opt.shuffle));
end
end

function y_sr = phase_randomize(y)
% PHASE_RANDOMIZE  Phase-randomized surrogate with preserved amplitude spectrum.
% Ensures Hermitian symmetry for a real IFFT; keeps DC/Nyquist terms intact.
y = y(:); T = numel(y);
Yf = fft(y);
half = floor(T/2);
mag = abs(Yf); ph = angle(Yf);
if T>2
    randphi = 2*pi*rand(half-1,1) - pi; % random phases for 1..half-1
    ph(2:half) = randphi;
    ph(T-half+2:T) = -flipud(randphi);  % negative freqs mirrored
end
Yf_new = mag .* exp(1i*ph);
y_sr = real(ifft(Yf_new));
end

function y_bs = block_shuffle(y, B)
% BLOCK_SHUFFLE  Permute contiguous blocks of length B (last block may be shorter).
y = y(:); T = numel(y);
idx = [1:B:T, T+1];
nblk = numel(idx)-1;
order = randperm(nblk);
y_bs = zeros(T,1,'like',y);
pos = 1;
for k = 1:nblk
    b = order(k);
    seg = y(idx(b):idx(b+1)-1);
    y_bs(pos:pos+numel(seg)-1) = seg;
    pos = pos + numel(seg);
end
end

function [clusters, masses] = clusters_from_mask(mask, weights)
% CLUSTERS_FROM_MASK  Find contiguous supra-threshold clusters and compute mass.
%   mask    : logical [1 x T] (true where observed > threshold)
%   weights : [1 x T]          (e.g., observed - threshold at each time)
% Returns:
%   clusters: [K x 3] array, columns = [start_idx, end_idx, mass]
%   masses  : [K x 1] vector of cluster masses
mask = logical(mask(:))'; T = numel(mask);
clusters = []; masses = [];
if T==0 || ~any(mask), return; end
d = diff([false, mask, false]);
starts = find(d==1);
ends   = find(d==-1) - 1;
K = numel(starts);
clusters = zeros(K,3);
masses   = zeros(K,1);
for k = 1:K
    s = starts(k); e = ends(k);
    clusters(k,:) = [s, e, sum(weights(s:e),'omitnan')];
    masses(k) = clusters(k,3);
end
end

function tf = tfce_1d(z, E, H, dh)
% TFCE_1D  Threshold-Free Cluster Enhancement for a 1-D statistic series.
%   tf = tfce_1d(z, E, H, dh)
% Inputs:
%   z  : [1 x T] (or [T x 1]) studentized statistic across time (higher = more evidence)
%   E  : extent exponent (default 0.5)
%   H  : height exponent (default 2.0)
%   dh : threshold step in z units (default 0.1)
% Output:
%   tf : TFCE-enhanced statistic per time point (same shape as z).
%
% Algorithm (Smith & Nichols 2009): integrate (extent^E * height^H) over thresholds h from 0..max(z).
z = z(:)';                      % 1 x T
T = numel(z);
zmax = max(z);
if zmax <= 0
    tf = zeros(size(z));
    tf = reshape(tf, 1, []);
    return;
end
h_vals = 0:dh:zmax;
tf = zeros(1,T);
for h = h_vals
    mask = (z > h);
    if ~any(mask), continue; end
    % run-length encoding to get extents
    d = diff([false, mask, false]);
    starts = find(d==1);
    ends   = find(d==-1) - 1;
    for i = 1:numel(starts)
        s = starts(i); e = ends(i);
        ext = (e - s + 1);                 % extent in samples
        height_vec = (z(s:e) - h);         % amount above threshold
        tf(s:e) = tf(s:e) + (ext^E) .* (height_vec.^H) * dh;
    end
end
tf = reshape(tf, size(z));
end

function out = tern(cond, a, b)
% TERN  tiny ternary helper (kept local to avoid branching clutter).
if cond, out = a; else, out = b; end
end
