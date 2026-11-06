function stats = rsa_mrqap(S_neural, S_behav, S_cov, varargin)
% RSA_MRQAP  MRQAP for ISC-RSA with optional covariates (FL/DSP), rich output.
% (Memory-safe: uses QR residualization; never forms P = X(X'X)^{-1}X'.)
%
% Ordinary least squares (dyad-long) + node-label permutations that preserve
% dyadic dependence (optionally within strata). Supports time-resolved Y
% (N×N×T), max-T correction across time, rank-based regression, and per-
% predictor permutation p-values (main-only by default, or all predictors).
%
% USAGE
%   % (1) Mantel-equivalent MRQAP (no covariates)
%   stats = rsa_mrqap(S_neural, S_behav, []);
%
%   % (2) One covariate
%   stats = rsa_mrqap(S_neural, S_behav, S_cov1);
%
%   % (3) Multiple covariates (cell)
%   stats = rsa_mrqap(S_neural, S_behav, {S_cov1, S_cov2}, ...
%                     'scheme','DSP', 'test','all');
%
% INPUTS
%   S_neural : [N x N] or [N x N x T]
%              Neural similarity (or distance) matrix, possibly time-resolved.
%
%   S_behav  : [N x N]
%              Behavioral similarity (or distance) matrix (main predictor).
%
%   S_cov    : [] | [N x N] | cell of [N x N]
%              Optional dyadic covariate matrices (each N×N). Can be:
%                  []          → no covariates
%                  [N x N]     → single covariate
%                  {A,B,...}   → multiple covariates
%
% NAME-VALUE PAIRS
%   'scheme'    : 'FL' (default) | 'DSP'
%                 Permutation scheme:
%                   FL  → Freedman–Lane
%                   DSP → Double semi-partialling (requires ≥1 covariate).
%                         The focal predictor is residualized on the nuisance
%                         design, node-permuted, and tested with the original
%                         nuisance design retained (Dekker et al., 2007,
%                         Eq. 17), evaluated through an equivalent FWL fit.
%
%   'vectorize' : 'lower' (default) | 'upper' | 'alloff'
%                 Which dyads to include:
%                   'lower'  → strict lower triangle (i>j)
%                   'upper'  → strict upper triangle (i<j)
%                   'alloff' → all off-diagonal entries
%
%   'rank'      : false (default)
%                 If true, rank-transform y/x/covariates (Spearman-like).
%
%   'nPerm'     : 5000
%                 Number of node-label permutations (0 = no permutations).
%
%   'twoTailed' : true
%                 If true, use two-tailed tests; otherwise one-tailed.
%
%   'maxT'      : true
%                 If T>1, apply max-T correction across time points.
%
%   'seed'      : [] (default)
%                 Random seed for reproducibility (passed to rng).
%
%   'nodePermutations' : [] (default) | [B x N] numeric | cell array
%                 Optional pre-generated node-label permutations. Each row
%                 (or cell) must contain a permutation of 1:N and is applied
%                 as A(P,P). When supplied, these permutations are used
%                 exactly as given and determine B; 'nPerm' and 'seed' do
%                 not generate or replace them. This is useful for sharing
%                 the same permutation index across all time points.
%
%   'numWorkers' : 0 (default)
%                 Maximum workers used by permutation parfor loops. Zero
%                 executes them serially and preserves legacy behavior.
%
%   'strata'    : []
%                 Optional length-N vector of stratum labels. Permutations
%                 are then restricted within strata (e.g., site / batch).
%
%   'expectSym' : true
%                 If true, symmetrize all N×N inputs and zero their diagonals.
%
%   'direction' : 'auto' (default) | 'similarity' | 'distance'
%                 Controls sign alignment of S_behav relative to S_neural:
%                   'auto'       → Spearman check; flip S_behav if negative.
%                   'similarity' → assume larger = more similar.
%                   'distance'   → assume larger = more distant (internally flipped).
%
%   'test'      : 'main' (default) | 'all'
%                 Which predictors to compute permutation p-values for:
%                   'main' → only main predictor (S_behav, column 2)
%                   'all'  → all non-intercept predictors. Under DSP the
%                            intercept has no permutation test and is NaN.
%
%   'names'     : {} or cellstr, length = 1 + 1 + p_cov
%                 Names of predictors including intercept, e.g.:
%                   {'(Intercept)','S_behav','SameSex','AgeSim'}
%
%   'stat'      : 't' (default) | 'beta'
%                 Which statistic to use in permutation test:
%                   't'    → t-values (recommended; more nearly pivotal)
%                   'beta' → raw regression coefficients
%
% OUTPUT (struct)
%   OLS-level quantities (no permutation):
%     .beta             [p x T]   OLS coefficients (incl. intercept).
%     .beta_main        [1 x T]   Coefficients for main predictor (column 2).
%     .se               [p x T]   Standard errors.
%     .tval             [p x T]   t-statistics.
%     .ols              struct    Per-time OLS diagnostics:
%                                  .n, .p, .dof, .sigma, .R2, .adjR2, .SSE,
%                                  .AIC, .BIC
%     .partialR2        [p x T]   Partial R² for each predictor at each time,
%                                 controlling for all other predictors:
%                                   R2_partial(j,t) = t_j(t)^2 / (t_j(t)^2 + df_res)
%     .partialR2_main   [1 x T]   Partial R² for the main predictor (S_behav).
%
%   Permutation results:
%     .p_main           [1 x T]   Permutation p-values for main predictor.
%     .permDist_main    [...]     Permutation distribution for main predictor
%                                 (shape depends on maxT).
%     .p_all            [p x T]   Permutation p-values for all predictors
%                                 (if 'test' = 'all'; otherwise empty).
%     .permDist_all     1 x p cell array of permutation distributions
%                                 (if 'test' = 'all'; otherwise empty).
%
%   Misc / bookkeeping:
%     .vecMask          [N x N] logical mask of dyads actually analyzed.
%     .scheme           'FL' or 'DSP' (effective scheme used).
%     .names            cellstr predictor names (including intercept).
%     .info             struct with options and meta-info:
%                          .rank, .nPerm, .twoTailed, .maxT, .strata,
%                          .vectorize, .direction, .timeResolved,
%                          .test, .p_all_cols, .n_dyads, .statUsed,
%                          .nodePermutationsProvided, .numWorkers
%
% NOTES
%   • The same dyad set (vecMask) is used for all fits and permutations.
%   • Node-label permutations (rows/cols jointly) preserve dyadic dependence.
%   • DSP follows Dekker, Krackhardt, and Snijders (2007), Psychometrika,
%     72, 563–581, https://doi.org/10.1007/s11336-007-9016-1.
%   • Partial R² is purely observational (no permutation), computed from
%     the OLS t-statistics and residual degrees of freedom.

% -------------------- Parse name-value pairs --------------------
ip = inputParser;
ip.addParameter('scheme','FL');
ip.addParameter('vectorize','lower');
ip.addParameter('rank',false,@islogical);
ip.addParameter('nPerm',5000,@(x)isnumeric(x)&&isscalar(x)&&x>=0);
ip.addParameter('twoTailed',true,@islogical);
ip.addParameter('maxT',true,@islogical);
ip.addParameter('seed',[]);
ip.addParameter('nodePermutations',[], ...
    @(x) isempty(x) || isnumeric(x) || iscell(x));
ip.addParameter('numWorkers',0, ...
    @(x) isnumeric(x) && isscalar(x) && x>=0 && x==fix(x));
ip.addParameter('strata',[]);
ip.addParameter('expectSym',true,@islogical);
ip.addParameter('direction','auto');
ip.addParameter('test','main');                 % 'main' | 'all'
ip.addParameter('names',{});                    % optional column names
ip.addParameter('stat','t', @(s) any(strcmpi(s,{'beta','t','tval'})));
ip.parse(varargin{:});
opt = ip.Results;
if isempty(opt.nodePermutations) && ~isempty(opt.seed), rng(opt.seed); end
useT = any(strcmpi(opt.stat,{'t','tval'}));

% -------------------- Basic checks --------------------
[N1,N2,maybeT] = size(S_neural);
assert(N1==N2, 'S_neural must be square.');
assert(all(size(S_behav,1:2)==[N1 N2]), 'S_behav size mismatch.');
isTime = (ndims(S_neural)==3 && maybeT>1);
T      = max(1, maybeT);

% -------------------- Normalize covariate container --------------------
if isempty(S_cov)
    covMats = {};
elseif iscell(S_cov)
    covMats = S_cov;
else
    assert(ismatrix(S_cov) && all(size(S_cov)==[N1 N2]), 'S_cov must be [N x N].');
    covMats = {S_cov};
end
p_cov = numel(covMats);

% -------------------- Names for predictors (incl. intercept) --------------------
if isempty(opt.names)
    names = cell(1, 2 + p_cov);   % [Intercept, S_behav, cov1..covK]
    names{1} = '(Intercept)';
    names{2} = 'S_behav';
    for k = 1:p_cov
        names{2+k} = sprintf('cov%d',k);
    end
else
    names = opt.names;
    assert(numel(names)==2+p_cov, ...
        'names must be length 1+1+p_cov (including intercept).');
end

% -------------------- Symmetry & zero diagonals --------------------
enforce_sym0 = @(A) setdiag0(0.5*(A + A.'));
if opt.expectSym
    S_behav = enforce_sym0(S_behav);
    if isTime
        for t = 1:T
            S_neural(:,:,t) = enforce_sym0(S_neural(:,:,t));
        end
    else
        S_neural = enforce_sym0(S_neural);
    end
    for c = 1:p_cov
        covMats{c} = enforce_sym0(covMats{c});
    end
end

% -------------------- Vectorization (geometry) --------------------
switch lower(string(opt.vectorize))
    case "lower"
        geom = tril(true(N1),-1);
    case "upper"
        geom = triu(true(N1), 1);
    case "alloff"
        geom = ~eye(N1);
    otherwise
        error('rsa_mrqap:vectorize','Unknown vectorize mode.');
end

% -------------------- Availability mask across ALL variables/T --------------------
avail = isfinite(S_behav);
if isTime
    for t = 1:T
        avail = avail & isfinite(S_neural(:,:,t));
    end
else
    avail = avail & isfinite(S_neural);
end
for c = 1:p_cov
    avail = avail & isfinite(covMats{c});
end
avail = avail & geom;
if ~any(avail(:))
    error('No valid dyads after masking/NA handling.');
end

% -------------------- Vectorize to dyad-long --------------------
if isTime
    y = zeros(nnz(avail), T);
    for t = 1:T
        tmp = S_neural(:,:,t);
        y(:,t) = tmp(avail);
    end
else
    y = S_neural(avail);
end
x_main = S_behav(avail);
Xcov   = [];
if p_cov>0
    for c = 1:p_cov
        Xcov = [Xcov, covMats{c}(avail)]; %#ok<AGROW>
    end
end

% -------------------- Direction alignment (cosmetic) --------------------
if ~strcmpi(opt.direction,'auto')
    if strcmpi(opt.direction,'distance')
        x_main = -x_main;
    end
else
    if isTime
        ychk = mean(y,2,'omitnan');
    else
        ychk = y;
    end
    rchk = corr(ychk, x_main, 'Type','Spearman', 'Rows','pairwise');
    if ~isnan(rchk) && rchk < 0
        x_main = -x_main;
    end
end

% -------------------- Optional rank transform --------------------
if opt.rank
    x_main = tiedrank(x_main);
    if ~isempty(Xcov)
        for c = 1:size(Xcov,2)
            Xcov(:,c) = tiedrank(Xcov(:,c));
        end
    end
    if isTime
        for t = 1:T
            y(:,t) = tiedrank(y(:,t));
        end
    else
        y = tiedrank(y);
    end
end

% -------------------- Full design matrix --------------------
X_full = [ones(numel(x_main),1), x_main, Xcov];   % p_all = 1 + 1 + p_cov
p_all  = size(X_full,2);

useDSP = strcmpi(opt.scheme,'DSP');
if useDSP && isempty(Xcov)
    % DSP requires at least one covariate; if none, fall back to FL
    useDSP = false;
end

% Precompute reduced designs for FL (one per predictor)
if ~useDSP
    X_red_all = cell(1, p_all);
    for j = 1:p_all
        keep = true(1,p_all); 
        keep(j) = false;
        X_red_all{j} = X_full(:, keep);
    end
end

% -------------------- Observed OLS (QR) --------------------
[beta_obs, t_obs, se_obs, ols_info] = ols_full_qr(y, X_full); % p×T
obs_stat = beta_obs;
if useT
    obs_stat = t_obs;
end

stats.beta      = beta_obs;
stats.beta_main = beta_obs(2,:);   % main predictor (S_behav), across time
stats.se        = se_obs;
stats.tval      = t_obs;
stats.ols       = ols_info;

% -------------------- Partial R² (per predictor, per time) --------------------
% For each predictor j and time t:
%   R2_partial(j,t) = t(j,t)^2 / ( t(j,t)^2 + df_res )
% where df_res = residual degrees of freedom (n - p).
df_res = ols_info.dof;              % scalar (same for all times)
stats.partialR2      = (t_obs.^2) ./ (t_obs.^2 + df_res);  % p×T
stats.partialR2_main = stats.partialR2(2,:);               % 1×T, main predictor

% -------------------- Permutations --------------------
if isempty(opt.nodePermutations)
    B         = opt.nPerm;
    perms_idx = {};
else
    perms_idx = normalize_label_perms(opt.nodePermutations, N1, opt.strata);
    B         = numel(perms_idx);
end
pvals_main    = NaN(1,T);
pvals_all     = NaN(p_all,T);
permDist_main = [];
permDist_all  = [];

if B > 0
    % Generate node-label permutations unless supplied by the caller.
    if isempty(perms_idx)
        perms_idx = generate_label_perms(N1, B, opt.strata);
    end
    wantAll   = strcmpi(opt.test,'all');
    numWorkers = opt.numWorkers;

    % ---- MAIN effect p-values (column 2) ----
    if ~useDSP
        % Freedman–Lane for main: reduced model excludes column 2
        X_red_main = X_red_all{2};
        [b_red, ~] = ols_full_qr(y, X_red_main);
        yhat_red   = X_red_main * b_red;
        e          = y - yhat_red;     % residuals, (#dyads)×T

        rawPermStats = nan(B,T);
        parfor (b = 1:B, numWorkers)
            P   = perms_idx{b};
            e_b = apply_perm_to_residuals(e, N1, avail, P, T);
            y_b = yhat_red + e_b;
            [beta_b, t_b] = ols_full_qr(y_b, X_full);
            stat_b = beta_b(2,:);
            if useT
                stat_b = t_b(2,:);
            end
            rawPermStats(b,:) = stat_b;
        end
        permDist_main = collapse_permutation_time( ...
            rawPermStats, T>1 && opt.maxT, opt.twoTailed);

    else
        % Dekker DSP for main (Dekker et al., 2007, Eq. 17).
        % The focal predictor is first residualized on the nuisance design,
        % then node-permuted. Because permutation generally destroys its
        % orthogonality to the nuisance design, it is residualized again in
        % every permuted fit. This FWL calculation is exactly equivalent to
        % fitting original Y on the permuted focal residual plus original Z.
        keep = true(1,p_all); 
        keep(2) = false;
        Qj      = qr_Q(X_full(:,keep));               % economy QR
        y_perp  = y  - Qj*(Qj'*y);                    % residualized Y
        x_perp  = X_full(:,2) - Qj*(Qj'*X_full(:,2)); % residualized main predictor

        rawPermStats = nan(B,T);
        parfor (b = 1:B, numWorkers)
            P   = perms_idx{b};
            x_b = apply_perm_to_predictor(x_perp, N1, avail, P);
            x_b = x_b - Qj*(Qj'*x_b);
            [beta_b, t_b] = ols_fwl_target(y_perp, x_b, df_res);
            stat_b = beta_b;
            if useT
                stat_b = t_b;
            end
            rawPermStats(b,:) = stat_b;
        end
        permDist_main = collapse_permutation_time( ...
            rawPermStats, T>1 && opt.maxT, opt.twoTailed);
    end

    % Permutation p for main effect
    if T>1 && opt.maxT
        pvals_main = arrayfun(@(st) perm_pvalue_maxT(permDist_main, st, opt.twoTailed), ...
                              obs_stat(2,:));
    else
        pvals_main = arrayfun(@(tix) perm_pvalue_vec(permDist_main(:,tix), ...
                                                     obs_stat(2,tix), opt.twoTailed), ...
                              1:T);
    end

    % ---- ALL predictors p-values (optional) ----
    if wantAll
        permDist_all = cell(1, p_all);
        pvals_all    = NaN(p_all, T);

        for j = 1:p_all
            if useDSP && j==1
                % The intercept is part of every nuisance design and has no
                % meaningful node-permutation test under DSP.
                permDist_all{j} = [];
                pvals_all(j,:) = NaN;
                continue;
            end
            if ~useDSP
                % FL for predictor j
                X_red_j = X_red_all{j};
                [b_red_j, ~] = ols_full_qr(y, X_red_j);
                yhat_red_j   = X_red_j * b_red_j;
                e_j          = y - yhat_red_j;

                rawPermStats = nan(B,T);
                parfor (b = 1:B, numWorkers)
                    P   = perms_idx{b};
                    e_b = apply_perm_to_residuals(e_j, N1, avail, P, T);
                    y_b = yhat_red_j + e_b;
                    [beta_b, t_b] = ols_full_qr(y_b, X_full);
                    stat_b = beta_b(j,:);
                    if useT
                        stat_b = t_b(j,:);
                    end
                    rawPermStats(b,:) = stat_b;
                end
                pd = collapse_permutation_time( ...
                    rawPermStats, T>1 && opt.maxT, opt.twoTailed);

                permDist_all{j} = pd;

                if T>1 && opt.maxT
                    pvals_all(j,:) = arrayfun(@(st) perm_pvalue_maxT(pd, st, opt.twoTailed), ...
                                              obs_stat(j,:));
                else
                    for t = 1:T
                        pvals_all(j,t) = perm_pvalue_vec(pd(:,t), ...
                                                         obs_stat(j,t), opt.twoTailed);
                    end
                end

            else
                % Dekker DSP for predictor j, using the same FWL-equivalent
                % calculation as the main-effect block above.
                keep = true(1,p_all); 
                keep(j) = false;
                Qj      = qr_Q(X_full(:,keep));
                y_perp  = y - Qj*(Qj'*y);
                x_perp  = X_full(:,j) - Qj*(Qj'*X_full(:,j));

                rawPermStats = nan(B,T);
                parfor (b = 1:B, numWorkers)
                    P   = perms_idx{b};
                    x_b = apply_perm_to_predictor(x_perp, N1, avail, P);
                    x_b = x_b - Qj*(Qj'*x_b);
                    [beta_b, t_b] = ols_fwl_target(y_perp, x_b, df_res);
                    stat_b = beta_b;
                    if useT
                        stat_b = t_b;
                    end
                    rawPermStats(b,:) = stat_b;
                end
                pd = collapse_permutation_time( ...
                    rawPermStats, T>1 && opt.maxT, opt.twoTailed);

                permDist_all{j} = pd;

                if T>1 && opt.maxT
                    pvals_all(j,:) = arrayfun(@(st) perm_pvalue_maxT(pd, st, opt.twoTailed), ...
                                              obs_stat(j,:));
                else
                    for t = 1:T
                        pvals_all(j,t) = perm_pvalue_vec(pd(:,t), ...
                                                         obs_stat(j,t), opt.twoTailed);
                    end
                end
            end
        end
    end
end

% -------------------- Package output --------------------
stats.p_main        = pvals_main;
stats.permDist_main = permDist_main;

if B>0 && strcmpi(opt.test,'all')
    stats.p_all        = pvals_all;
    stats.permDist_all = permDist_all;
else
    stats.p_all        = [];
    stats.permDist_all = [];
end

stats.vecMask = avail;
stats.scheme  = iff(useDSP,'DSP','FL');
stats.names   = names;
stats.info    = struct( ...
    'rank',       opt.rank, ...
    'nPerm',      B, ...
    'twoTailed',  opt.twoTailed, ...
    'maxT',       logical(opt.maxT), ...
    'strata',     opt.strata, ...
    'vectorize',  opt.vectorize, ...
    'direction',  opt.direction, ...
    'timeResolved', isTime, ...
    'test',       opt.test, ...
    'p_all_cols', p_all, ...
    'n_dyads',    nnz(avail), ...
    'nodePermutationsProvided', ~isempty(opt.nodePermutations), ...
    'numWorkers', opt.numWorkers, ...
    'dspImplementation', iff(useDSP,'Dekker2007_Eq17_FWL',''), ...
    'statUsed',   iff(useT,'t','beta') ...
    );
end % ===== END MAIN =====

% ==================== Helper functions ====================

function A = setdiag0(A)
% Zero the diagonal of a square matrix.
    A(1:size(A,1)+1:end) = 0;
end

function Q = qr_Q(X)
% Economy-size QR and return Q only (n x p).
    [Q,~] = qr(X,0);
end

function [BETA, TVAL, SE, OLS] = ols_full_qr(Y, X)
% OLS_FULL_QR  Ordinary least squares via thin QR.
%
%   Solves Y = X BETA + E without explicitly forming (X'X)^{-1}.
%   Uses economy-size QR factorization X = Q R (n×p, p×p).
%
% INPUT
%   Y : [n x T] response(s)
%   X : [n x p] design matrix (full rank assumed)
%
% OUTPUT
%   BETA : [p x T] OLS coefficients.
%   TVAL : [p x T] t-statistics.
%   SE   : [p x T] standard errors.
%   OLS  : struct with fields:
%            .n, .p, .dof, .sigma, .R2, .adjR2, .SSE, .AIC, .BIC

    if isvector(Y), Y = Y(:); end
    [n,p] = size(X);
    Tt    = size(Y,2);

    % Thin QR
    [Q,R] = qr(X,0);           % X = Q (n×p), R (p×p)
    QtY   = Q' * Y;            % p×T

    % Solve R * BETA = QtY (back-substitution; R upper-triangular)
    BETA  = R \ QtY;           % p×T

    % Residuals
    E     = Y - Q*(QtY);       % n×T
    dof   = max(n - p, 1);     % residual degrees of freedom
    s2    = sum(E.^2, 1) ./ dof;  % 1×T

    % Covariance of BETA: (X'X)^{-1} = inv(R)*inv(R') (p small)
    Rin   = inv(R);
    covB  = Rin * Rin.';           % p×p
    SE    = sqrt(diag(covB)) * sqrt(s2);  % p×T
    TVAL  = BETA ./ SE;

    SSE   = sum(E.^2, 1);          % 1×T
    TSS   = sum( (Y - mean(Y,1)).^2, 1 ); % total sum of squares
    R2    = 1 - SSE ./ TSS;
    adjR2 = 1 - (1-R2) .* ((n-1)./max(n-p,1));
    sigma = sqrt(s2);
    k     = p;
    AICt  = n.*log(SSE./n) + 2*k;
    BICt  = n.*log(SSE./n) + k*log(n);

    OLS = struct('n',n,'p',p,'dof',dof,'sigma',sigma,'R2',R2, ...
                 'adjR2',adjR2,'SSE',SSE,'AIC',AICt,'BIC',BICt);
end

function [BETA, TVAL] = ols_fwl_target(Yperp, xperp, fullModelDof)
% OLS_FWL_TARGET  Focal coefficient/statistic after nuisance residualization.
%
% Yperp and xperp have both been residualized against the same nuisance
% design. The coefficient and t statistic equal those from the full model
% containing x plus that nuisance design when the full-model residual
% degrees of freedom are used.
    if isvector(Yperp), Yperp = Yperp(:); end
    xperp = xperp(:);
    sumSquaresX = xperp' * xperp;
    if ~isfinite(sumSquaresX) || sumSquaresX <= eps(max(1,sumSquaresX))
        BETA = NaN(1,size(Yperp,2));
        TVAL = NaN(1,size(Yperp,2));
        return;
    end
    crossProduct = xperp' * Yperp;
    BETA = crossProduct ./ sumSquaresX;
    % Algebraic SSE avoids materializing an n-by-T residual array for every
    % permutation, which is important for time-resolved models.
    residualSumSquares = sum(Yperp.^2,1) - (crossProduct.^2 ./ sumSquaresX);
    residualSumSquares = max(residualSumSquares,0);
    residualVariance = residualSumSquares ./ max(fullModelDof,1);
    standardError = sqrt(residualVariance ./ sumSquaresX);
    TVAL = BETA ./ standardError;
end

function perms = generate_label_perms(N, B, strata)
% GENERATE_LABEL_PERMS  Node-label permutations with optional strata.
%
%   Returns a cell array of B permutations, each a 1×N vector P such that
%   permuted matrices are A(P,P). If strata is provided, permutations are
%   restricted within strata blocks.
    perms = cell(1,B);
    if isempty(strata)
        for b = 1:B
            perms{b} = randperm(N);
        end
    else
        strata = strata(:);
        assert(numel(strata)==N,'strata length must be N.');
        [~,~,gid] = unique(strata);
        blocks = arrayfun(@(g)find(gid==g), unique(gid), 'uni',0);
        for b = 1:B
            P = (1:N)'; %#ok<AGROW>
            for k = 1:numel(blocks)
                blk = blocks{k};
                P(blk) = blk(randperm(numel(blk)));
            end
            perms{b} = P(:).';
        end
    end
end

function perms = normalize_label_perms(inputPerms, N, strata)
% NORMALIZE_LABEL_PERMS  Validate caller-supplied permutations.
%
%   Accepts a B-by-N numeric matrix or a cell array containing B vectors.
%   Returns the internal 1-by-B cell representation used by rsa_mrqap.
    if isnumeric(inputPerms)
        assert(ismatrix(inputPerms) && size(inputPerms,2)==N, ...
            'rsa_mrqap:nodePermutationsSize', ...
            'nodePermutations must have N columns.');
        B = size(inputPerms,1);
        perms = cell(1,B);
        for b = 1:B
            perms{b} = double(inputPerms(b,:));
        end
    else
        B = numel(inputPerms);
        perms = cell(1,B);
        for b = 1:B
            perms{b} = double(inputPerms{b}(:).');
        end
    end

    expected = 1:N;
    strataCol = strata(:);
    if ~isempty(strataCol)
        assert(numel(strataCol)==N, 'strata length must be N.');
    end
    for b = 1:B
        P = perms{b};
        assert(numel(P)==N && all(isfinite(P)) && ...
               all(P==fix(P)) && isequal(sort(P), expected), ...
            'rsa_mrqap:nodePermutationsInvalid', ...
            'Each node permutation must contain every integer from 1 to N exactly once.');
        if ~isempty(strataCol)
            assert(isequaln(strataCol(P(:)), strataCol), ...
                'rsa_mrqap:nodePermutationsStrata', ...
                'A supplied node permutation moves at least one node across strata.');
        end
    end
end

function e_perm = apply_perm_to_residuals(e, N, availMask, P, Tt)
% APPLY_PERM_TO_RESIDUALS  Permute residuals via node-label permutations.
%
%   Rebuild N×N residual matrices for each time, apply A(P,P), then
%   re-vectorize using the same dyad indices (availMask).
    e_perm = zeros(size(e));
    [I,J]  = find(availMask);
    for t = 1:Tt
        R = zeros(N);
        for k = 1:numel(I)
            R(I(k),J(k)) = e(k,t);
            R(J(k),I(k)) = e(k,t);
        end
        Rp = R(P,P);
        for k = 1:numel(I)
            e_perm(k,t) = Rp(I(k),J(k));
        end
    end
end

function xp = apply_perm_to_predictor(x, N, availMask, P)
% APPLY_PERM_TO_PREDICTOR  Permute a dyad-long predictor via node labels.
%
%   Rebuild an N×N matrix from vectorized predictor x (availMask), apply
%   A(P,P), then re-vectorize using the same dyad indices.
    xp      = zeros(size(x));
    [I,J]   = find(availMask);
    R       = zeros(N);
    for k = 1:numel(I)
        R(I(k),J(k)) = x(k);
        R(J(k),I(k)) = x(k);
    end
    Rp = R(P,P);
    for k = 1:numel(I)
        xp(k) = Rp(I(k),J(k));
    end
end

function output = collapse_permutation_time(rawStats, useMaxT, twoT)
% COLLAPSE_PERMUTATION_TIME  Retain B-by-T stats or reduce to max-T.
    if ~useMaxT
        output = rawStats;
    elseif twoT
        output = max(abs(rawStats),[],2).';
    else
        output = max(rawStats,[],2).';
    end
end

function p = perm_pvalue_maxT(permStats, obs, twoT)
% PERM_PVALUE_MAXT  Permutation p-value for max-T distribution.
    if twoT
        p = (1 + nnz(permStats >= abs(obs))) / (numel(permStats)+1);
    else
        p = (1 + nnz(permStats >= obs))     / (numel(permStats)+1);
    end
end

function p = perm_pvalue_vec(vecStats, obs, twoT)
% PERM_PVALUE_VEC  Permutation p-value from a vector of surrogate stats.
    if twoT
        p = (1 + nnz(abs(vecStats) >= abs(obs))) / (numel(vecStats)+1);
    else
        p = (1 + nnz(vecStats >= obs))           / (numel(vecStats)+1);
    end
end

function out = iff(cond,a,b)
% IFF  Inline if-else.
    if cond
        out = a;
    else
        out = b;
    end
end
