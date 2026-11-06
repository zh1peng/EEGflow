function [W, ISC, Y, A, p] = run_corrca_stream(varargin)
% RUN_CORRCA_STREAM  Streaming CorrCA on EEGLAB .set files (no stacking).
% Matches CorrCA version=2 exactly, given identical preprocessing as stacking.
%
% Example (your case):
% [W,ISC,Y,A] = movie.run_corrca_stream( ...
%    'study_path','/media/NAS/EEGdata/HBN_EEG_BIDS/', ...
%    'searchstring','^sub.*\eeg_prep.set$', ...
%    'subjects_to_include',1:10, ...
%    'subject_parser','(?<sub>sub-[^_]+)', ...
%    'StartMarker','video_start', 'EndMarker','video_stop', 'PadSec',0, ...
%    'locutoff',1, 'hicutoff',4, 'chan_exclude',{'E8','E26','E125','E128'}, ...
%    'movie_duration_sec',203.074, ...   % OR 'expected_length', T
%    'parallel',true, 'shrinkage',0.1, 'tsvd',3);
%
% Outputs mirror your stacking wrapper: [W, ISC, Y, A] (p only with 'fixed').

% ---------- Parse Name/Value ----------
p = inputParser; p.KeepUnmatched = false;
% Discovery / selection
addParameter(p,'study_path','',@(x)ischar(x)||isstring(x));
addParameter(p,'searchstring','.*\.set$',@ischar);
addParameter(p,'recursive',true,@islogical);
addParameter(p,'setFile',{},@(x)iscellstr(x)||isstring(x));
addParameter(p,'subjects_to_include','all',@(x) (ischar(x)&&strcmpi(x,'all')) || isnumeric(x));
addParameter(p,'subject_parser','(?<sub>.+)',@ischar);
% Channels / segment
addParameter(p,'chan_include',{},@(x)iscellstr(x)||isstring(x));
addParameter(p,'chan_exclude',{},@(x)iscellstr(x)||isstring(x));
addParameter(p,'StartMarker','',@(s)ischar(s)||isstring(s));
addParameter(p,'EndMarker','',@(s)ischar(s)||isstring(s));
addParameter(p,'PadSec',0,@isscalar);
% Resample-to-length (to match stacking)
addParameter(p,'movie_duration_sec',[],@(x) isempty(x) || (isscalar(x)&&x>0));
addParameter(p,'expected_length',[],@(x) isempty(x) || (isscalar(x)&&x>0));
% Preprocessing toggles (subset from collect_segments)
addParameter(p,'locutoff',[],@(x) isempty(x) || (isscalar(x)&&x>=0));
addParameter(p,'hicutoff',[],@(x) isempty(x) || (isscalar(x)&&x>=0));
addParameter(p,'csd',false,@islogical);
addParameter(p,'csd_lambda',1.0e-5,@isscalar);
addParameter(p,'csd_head_radius',10.0,@isscalar);
addParameter(p,'csd_m',4,@isscalar);
addParameter(p,'hilbert_env',false,@islogical);
% CorrCA numerics / execution
addParameter(p,'shrinkage',0,@(x)isnumeric(x)&&isscalar(x)&&x>=0&&x<=1);
addParameter(p,'tsvd',[],@(x) isempty(x) || (isscalar(x)&&x>0));
addParameter(p,'ridge',[],@(x) isempty(x) || (isscalar(x)&&x>=0));
addParameter(p,'parallel',false,@(x)islogical(x)&&isscalar(x));
addParameter(p,'engine','parfor',@(s)ischar(s)||isstring(s));
addParameter(p,'verbose',true,@(x)islogical(x)&&isscalar(x));
% Evaluation-only (fixed W) and Y control
addParameter(p,'fixed',[],@(x) isempty(x) || isnumeric(x));
addParameter(p,'topk',0,@(x)isnumeric(x)&&isscalar(x)&&x>=0); % limit Y comps (0->all)
parse(p,varargin{:});
opt = p.Results;

assert(~isempty(opt.StartMarker) && ~isempty(opt.EndMarker), 'StartMarker/EndMarker required.');
assert( xor( isempty(opt.movie_duration_sec), isempty(opt.expected_length) ) || ...
       (isempty(opt.movie_duration_sec) && isempty(opt.expected_length)), ...
       'Use either movie_duration_sec OR expected_length (or neither).');

% ---------- Build file list ----------
if isempty(opt.setFile)
    assert(~isempty(opt.study_path) && isfolder(opt.study_path), 'study_path not found.');
    [paths, names] = filesearch_regexp(opt.study_path, opt.searchstring, opt.recursive);
    assert(~isempty(names), 'No .set files found by searchstring.');
    if exist('natsort','file'), [~,si]=natsort(names); paths=paths(si); names=names(si); end
    setFiles = fullfile(paths, names);
else
    setFiles = cellstr(opt.setFile);
end
if isnumeric(opt.subjects_to_include)
    idx = unique(opt.subjects_to_include(:)');
    idx = idx(idx>=1 & idx<=numel(setFiles));
    setFiles = setFiles(idx);
end
N_all = numel(setFiles); assert(N_all>0,'Empty file list.');

% ---------- Pass 0: determine D and T = min post-preproc length ----------
if opt.verbose, fprintf('[stream] Scanning %d subjects to infer common T and D...\n', N_all); end
% valid = false(N_all,1); lens = zeros(N_all,1); D0 = [];
% for i=1:N_all
%     try
%         Xi = preproc_one(setFiles{i}, opt);   % [D x Ti]
%         if isempty(D0), D0 = size(Xi,1); end
%         if size(Xi,1) ~= D0, warning('Skip %s: channel mismatch', setFiles{i}); continue; end
%         valid(i) = true;
%         lens(i)  = size(Xi,2);
%     catch ME
%         warning('Skip %s: %s', setFiles{i}, ME.message);
%     end
% end
% setFiles = setFiles(valid);
% N = numel(setFiles);
% assert(N>1, 'Need at least 2 valid subjects.');
% D = D0;
% T = min(lens(valid));
N = numel(setFiles);
% Modified Pass 0 section
if ~isempty(opt.expected_length)
    T = opt.expected_length;
    fprintf('[stream] Enforcing fixed T=%d provided by user.\n', T);
    % Just load one file to get D (channels)
    Xi = preproc_one(setFiles{1}, opt);
    D = size(Xi,1);
else
    % Fallback to your original logic if expected_length is not provided
    Xi = preproc_one(setFiles{1}, opt);
    D = size(Xi,1);
    T = size(Xi,2);
end

if opt.verbose, fprintf('[stream] Using D=%d channels, T=%d samples, N=%d subjects.\n', D, T, N); end

% ---------- Pass 1: accumulate S and U (CorrCA v2, demeaned over time) ----------
if opt.parallel && havePCT()
    if opt.verbose, fprintf('[stream] Accumulating in parallel...\n'); end
    [S, U] = accumulate(setFiles, D, T, opt);
else
    if opt.verbose, fprintf('[stream] Accumulating serially...\n'); end
    S = zeros(D,D,'double');
    U = zeros(T,D,'double');             % sum of Xc (time-demeaned) across subjects
    for i=1:N
        Xi = preproc_one(setFiles{i}, opt);        % [D x Ti]
        Xi = Xi(:,1:T);                            % trim to common T
        X  = Xi.';                                 % [T x D]
        Xc = X - mean(X,1);                        % time-demean per channel (matches cov)
        S  = S + (Xc.' * Xc);                      % D x D
        U  = U + Xc;                               % T x D
    end
end

% Build Rw, Rt, Rb exactly as version 2
Rw = S / max(T-1,1);               % sum cov(X_i)
Rt = (U.' * U) / max(T-1,1);       % cov(sum X_i)
Rb = (Rt - Rw) / max(N-1,1);

% ---------- Solve CorrCA ----------
if isempty(opt.fixed)
    [W, ISC, ~, A] = corrca_from_R(Rw, Rb, ...
        'shrinkage', opt.shrinkage, 'tsvd', opt.tsvd, 'ridge', opt.ridge, 'normalizeW', true);
else
    % Evaluate only
    [W, ISC, ~, A] = corrca_from_R(Rw, Rb, 'fixed', opt.fixed);
end
p = [];   % p-values only meaningful when evaluating fixed W with provided Y (rarely used here)

% ---------- Pass 2 (optional): compute Y like stacking (X * W) ----------
WantY = nargout >= 3;
Y = [];
if WantY
    Kall = size(W,2);
    K = Kall;
    if opt.topk>0 && opt.topk < K, K = opt.topk; end
    if opt.parallel && havePCT()
        if opt.verbose, fprintf('[stream] Projecting Y (parallel)...\n'); end
        Y = zeros(T, K, N, 'single');
        parfor i=1:N
            Xi = preproc_one(setFiles{i}, opt);   % [D x Ti]
            Xi = Xi(:,1:T);
            X  = Xi.';                             % [T x D], NOTE: *not* demeaned for Y
            Y(:,:,i) = single(X * W(:,1:K));       % [T x K]
        end
    else
        if opt.verbose, fprintf('[stream] Projecting Y (serial)...\n'); end
        Y = zeros(T, K, N, 'single');
        for i=1:N
            Xi = preproc_one(setFiles{i}, opt);
            Xi = Xi(:,1:T);
            X  = Xi.';
            Y(:,:,i) = single(X * W(:,1:K));
        end
    end
end
end  % main

% ===================== helpers =====================

function tf = havePCT()
    tf = license('test','Distrib_Computing_Toolbox') && ~isempty(ver('parallel'));
end

function [S,U] = accumulate(files, D, T, opt)
    eng = lower(string(opt.engine));
    if eng=="auto"
        if havePCT(), eng = "spmd"; else, eng = "serial"; end
    end
    switch eng
        % case "spmd" % spmd does not work here
        %     [S,U] = accumulate_spmd(files, D, T, opt);
        case "parfor"
            [S,U] = accumulate_parfor(files, D, T, opt);
        case "serial"
            [S,U] = accumulate_serial(files, D, T, opt);
        otherwise
            error('Unknown engine: %s', eng);
    end
end

function [S,U] = accumulate_serial(files, D, T, opt)
    S = zeros(D,D,'double'); 
    U = zeros(T,D,'double');
    for i=1:numel(files)
        Xi = preproc_one(files{i}, opt);     % [D x Ti]
        Xi = Xi(:,1:T);
        X  = Xi.';                           % [T x D]
        Xc = X - mean(X,1);                  % time-demean per channel
        S  = S + (Xc.' * Xc);                % D x D
        U  = U + Xc;                         % T x D
    end
end

% function [S,U] = accumulate_spmd(files, D, T, opt)
%     pool = gcp('nocreate'); if isempty(pool), parpool; end
%     % Optional: avoid BLAS oversubscription on each worker
%     % pctRunOnAll maxNumCompThreads(1);
%     spmd
%         localS = zeros(D,D,'double');
%         localU = zeros(T,D,'double');
%         for idx = labindex:numlabs:numel(files)
%             Xi = preproc_one(files{idx}, opt);
%             Xi = Xi(:,1:T);
%             X  = Xi.'; Xc = X - mean(X,1);
%             localS = localS + (Xc.' * Xc);
%             localU = localU + Xc;
%         end
%         S = gplus(localS);
%         U = gplus(localU);
%     end
%     S = S{1}; U = U{1};
% end

function [S,U] = accumulate_parfor(files, D, T, opt)
    pool = gcp('nocreate'); if isempty(pool), parpool; end
    % Optional: avoid BLAS oversubscription on each worker
    % pctRunOnAll maxNumCompThreads(1);
    S = zeros(D,D,'double');    % reduction var
    U = zeros(T,D,'double');    % reduction var
    parfor i=1:numel(files)
        Xi = preproc_one(files{i}, opt);
        Xi = Xi(:,1:T);
        X  = Xi.'; Xc = X - mean(X,1);
        Si = Xc.' * Xc;
        Ui = Xc;
        S  = S + Si;            % parfor supports + reduction on arrays
        U  = U + Ui;
    end
end



function Xi = preproc_one(fpath, opt)
    % Load .set
    EEG = pop_loadset(fpath); EEG = eeg_checkset(EEG);

    % Include / exclude channels by label
    if ~isempty(opt.chan_include) && ~isempty(opt.chan_exclude)
        error('Use either chan_include or chan_exclude, not both.');
    end
    if ~isempty(opt.chan_include)
        EEG = pop_select(EEG, 'channel', opt.chan_include); EEG = eeg_checkset(EEG);
    end
    if ~isempty(opt.chan_exclude)
        EEG = pop_select(EEG, 'nochannel', opt.chan_exclude); EEG = eeg_checkset(EEG);
    end

    % Filtering as in collect_segments
    if (~isempty(opt.locutoff) && opt.locutoff>0) || (~isempty(opt.hicutoff) && opt.hicutoff>0)
        args = {};
        if ~isempty(opt.locutoff) && opt.locutoff>0, args = [args, {'locutoff', opt.locutoff}]; end
        if ~isempty(opt.hicutoff) && opt.hicutoff>0, args = [args, {'hicutoff', opt.hicutoff}]; end
        EEG = pop_eegfiltnew(EEG, args{:}); EEG = eeg_checkset(EEG);
    end

    % Crop movie segment
    crop_state = prep.crop_by_markers(struct('EEG', EEG), struct( ...
        'StartMarker', opt.StartMarker, 'EndMarker', opt.EndMarker, 'PadSec', opt.PadSec));
    EEG = crop_state.EEG;

    % Resample-to-length EXACTLY like your collect_segments (pchip to N_ref)
    if ~isempty(opt.movie_duration_sec) || ~isempty(opt.expected_length)
        if ~isempty(opt.movie_duration_sec)
            N_ref = round(opt.movie_duration_sec * EEG.srate);
        else
            N_ref = opt.expected_length;
        end
        if EEG.pnts ~= N_ref
            t_old = 1:EEG.pnts;
            t_new = linspace(1, EEG.pnts, N_ref);
            EEG.data = interp1(t_old, double(EEG.data)', t_new, 'pchip')';
            EEG.pnts = N_ref;
        end
    end

    % CSD (optional)
    if opt.csd
        assert(exist('CSD.m','file')==2 && exist('GetGH.m','file')==2, 'CSD toolbox not on path.');
        montage.lab = {EEG.chanlocs.labels};
        montage.theta = [EEG.chanlocs.sph_theta];
        montage.phi = [EEG.chanlocs.sph_phi];
        [G,H] = GetGH(montage, opt.csd_m);
        EEG.data = CSD(double(EEG.data), G, H, opt.csd_lambda, opt.csd_head_radius);
    end

    % Hilbert envelope (optional)
    if opt.hilbert_env
        Xtmp = double(EEG.data);
        for c = 1:size(Xtmp,1), Xtmp(c,:) = abs(hilbert(Xtmp(c,:))); end
        EEG.data = Xtmp;
    end

    Xi = double(EEG.data);   % [D x T_i]
end


function [W, ISC, Y, A, p] = corrca_from_R(Rw, Rb, varargin)
% CORRCA_FROM_R  CorrCA directly from within/between covariances (no 3-D stack).
% Matches "version 2" of Parra/Cohen when Rw/Rb are constructed accordingly.
%
% [W, ISC, Y, A, p] = corrca_from_R(Rw, Rb, 'Name',Value,...)
%
% Options:
%   'shrinkage'   : gamma in [0,1] shrink on Rw (default 0)
%   'tsvd'        : K (truncate eigenspectrum of Rw before solving; default [])
%   'ridge'       : extra ridge on Rw (default auto 1e-6*trace(Rw)/D)
%   'fixed'       : W_fixed -> do not solve; just evaluate ISC/A (and p if 'Y' given)
%   'normalizeW'  : true/false L2-normalize columns when solving (default true)
%   'Y'           : [T x K x N] projections (only for 'fixed') to compute p-values
%
% Outputs mirror corrca.m: Y,p are [] unless using 'fixed'+'Y'.

p = inputParser;
p.addParameter('shrinkage', 0, @(x)isnumeric(x)&&isscalar(x)&&x>=0&&x<=1);
p.addParameter('tsvd', [], @(x) isempty(x) || (isscalar(x)&&x>0));
p.addParameter('ridge', [], @(x) isempty(x) || (isscalar(x)&&x>=0));
p.addParameter('fixed', [], @(x) isempty(x) || isnumeric(x));
p.addParameter('normalizeW', true, @(x)islogical(x)&&isscalar(x));
p.addParameter('Y', [], @(x) isempty(x) || (ndims(x)==3));
p.parse(varargin{:});
opt = p.Results;

[D1,D2] = size(Rw); assert(D1==D2, 'Rw must be square'); D = D1;
assert(all(size(Rb)==[D D]), 'Rb must be D x D');

% Evaluate only (fixed W)
if ~isempty(opt.fixed)
    W = opt.fixed;
    denom = max(diag(W' * Rw * W), eps);
    ISC  = real(diag(W' * Rb * W) ./ denom);
    A    = Rw * W * diag(1 ./ denom);
    Y    = [];
    p    = [];
    if ~isempty(opt.Y)
        % Parra-style F-stat p-values on provided Y = projections [T x K x N]
        Yk = opt.Y;                     % [T x K x N]
        x  = permute(Yk,[2 1 3]);       % [K x T x N]
        sw = sum(var(x,[],3),2) * (size(x,3)-1);
        st = var(reshape(x, size(x,1), []), [], 2) * (size(x,2)*size(x,3)-1);
        sb = st - sw;
        S  = sb ./ max(sw, eps);
        df2 = size(x,2)*(size(x,3)-1); df1 = size(x,2)-1;
        F  = (df2/df1) * S;
        p  = fcdf(F, df1, df2, 'upper');
        p  = double(p(:));
    end
    return;
end

% Regularize Rw (align with external/corrca: shrinkage only by default)
gamma = opt.shrinkage;
if isempty(opt.ridge) || opt.ridge==0
    Rwreg = (1-gamma)*Rw + gamma*mean(diag(Rw))*eye(D);
else
    Rwreg = (1-gamma)*Rw + gamma*mean(diag(Rw))*eye(D) + opt.ridge*eye(D);
end

% Solve generalized eig
if ~isempty(opt.tsvd)
    % TSVD should be based on unregularized Rw (like external/corrca), ignoring shrinkage
    K = min(opt.tsvd, rank(Rw));
    [U,Sv] = eig((Rw+Rw')/2,'vector'); [Sv,idx] = sort(real(Sv),'descend'); U = real(U(:,idx));
    K = min(K, sum(Sv>max(Sv)*eps));
    U = U(:,1:K); Sv = Sv(1:K);
    Rw_sub = diag(Sv);           % K x K
    Rb_sub = U' * Rb * U;        % K x K
    [Wsub, lam] = eig(Rb_sub, Rw_sub, 'vector');
    [lam,ord] = sort(real(lam),'descend'); Wsub = real(Wsub(:,ord));
    W = U * Wsub;                % D x K
else
    % Use Cholesky-based generalized eigensolver to mirror external/corrca
    try
        [W, Dmat] = eig(Rb, Rwreg, 'chol');
        lam = diag(Dmat);
    catch
        % Fallback: add a tiny ridge if needed for numerical PD of Rwreg
        epsR = 1e-12 * trace(Rw)/max(D,1);
        [W, Dmat] = eig(Rb, Rwreg + epsR*eye(D), 'chol');
        lam = diag(Dmat);
    end
    [lam,ord] = sort(real(lam),'descend'); W = real(W(:,ord));
end

if opt.normalizeW
    W = W * diag(1 ./ max(sqrt(sum(W.^2,1)), eps));
end

for k = 1:size(W,2)
    % numeric tolerance relative to column scale
    tol = 10*eps(class(W)) * max(1, norm(W(:,k), inf));
    idx = find(abs(W(:,k)) > tol, 1, 'first');   % first reliably non-zero
    if ~isempty(idx) && W(idx,k) < 0
        W(:,k) = -W(:,k);   % flip column
    end
end

ISC = real(diag(W' * Rb * W) ./ max(diag(W' * Rw * W), eps));
A   = Rw * W * diag(1 ./ max(diag(W' * Rw * W), eps));
Y   = [];
p   = [];
end
