function stats = rsa_mantel(S_neural, S_behav, varargin)
% RSA_MANTEL Intersubject RSA: correlate neural ISC with behavioral similarity.
%
%   stats = movie.rsa_mantel(S_neural, S_behav, 'Name',Value,...)
%
% INPUTS
%   S_neural : [N x N] (static) or [N x N x T] (time-resolved) neural similarity/ISC
%   S_behav  : [N x N] behavioral similarity (static)
%
% NAME-VALUE
%   'vectorize' : 'lower' (default) | 'upper' | 'alloff'
%   'method'    : 'spearman' (default) | 'pearson' | 'kendall'
%   'nPerm'     : 5000 (default, 0 = no permutations)
%   'twoTailed' : true (default)  % if false, one-tailed (positive direction)
%   'maxT'      : true (default; time-resolved only)
%   'seed'      : [] or numeric
%
% OUTPUT
%   stats.r        : scalar (static) or [1 x T]
%   stats.p        : p-value(s) (max-T corrected if applicable)
%   stats.permDist : permutation distribution (vector for maxT; matrix for ~maxT)
%   stats.vecMask  : logical mask used for vectorization (N×N)
%   stats.method, .vectorize, .nPerm, .twoTailed, .maxT

ip = inputParser;
ip.addParameter('vectorize','lower');
ip.addParameter('method','spearman');
ip.addParameter('nPerm',5000,@(x)isnumeric(x)&&isscalar(x)&&x>=0);
ip.addParameter('twoTailed',true,@islogical);
ip.addParameter('maxT',true,@islogical);
ip.addParameter('seed',[]);
ip.parse(varargin{:});
opt = ip.Results;

if ~isempty(opt.seed), rng(opt.seed); end

[N1,N2,maybeT] = size(S_neural);
assert(N1==N2, 'S_neural must be square');
assert(all(size(S_behav,1:2)==[N1 N2]), 'S_behav size mismatch');

isTime = (ndims(S_neural)==3 && maybeT>1);
T = max(1, maybeT);

% ---- Vectorization mask
switch lower(string(opt.vectorize))
    case "lower",  mask = tril(true(N1),-1);
    case "upper",  mask = triu(true(N1), 1);
    case "alloff", mask = ~eye(N1);
    otherwise, error('isc_rsa:vectorize','Unknown vectorize mode.');
end
mask_vec = mask(:);

% ---- Behavioral vector (off-diagonal)
y = S_behav(mask);

% ---- Observed correlation(s) (vectorized across T)
if ~isTime
    % static
    x = S_neural(mask); % (#pairs x 1)
    r_obs = corr(x, y, 'type', opt.method, 'rows','complete'); % 1x1
    r_obs = r_obs(:).'; % row
else
    % time-resolved: reshape to (N^2 x T), then mask rows
    X = reshape(S_neural, N1*N1, T);
    X = X(mask_vec, :);                      % (#pairs x T)
    r_obs = corr(X, y, 'type', opt.method, 'rows','complete'); % T x 1
    r_obs = r_obs(:).';                     % 1 x T
end

% ---- Permutation test (permute subjects jointly across rows/cols)
nP = opt.nPerm;
if nP==0
    pvals = NaN(size(r_obs));
    perm_stats = [];
else
    if ~isTime
        % static: single correlation per permutation
        perm_stats = nan(1,nP);
        for p = 1:nP
            idx = randperm(N1);
            xn = S_neural(idx, idx);
            perm_stats(p) = corr(xn(mask), y, 'type', opt.method, 'rows','complete');
        end
        if opt.twoTailed
            pvals = (1 + nnz(abs(perm_stats) >= abs(r_obs))) / (nP+1);
        else
            pvals = (1 + nnz(perm_stats >= r_obs)) / (nP+1);
        end
    else
        % time-resolved: compute all-T correlations per permutation (no inner T loop)
        if opt.maxT
            perm_stats = nan(1,nP); % max (abs or signed) over T per perm
            for p = 1:nP
                idx = randperm(N1);
                % permute subjects on both axes for all T at once
                Xp = reshape(S_neural(idx, idx, :), N1*N1, T);
                Xp = Xp(mask_vec, :);  % (#pairs x T)
                rp = corr(Xp, y, 'type', opt.method, 'rows','complete'); % T x 1
                rp = rp(:).';
                if opt.twoTailed
                    perm_stats(p) = max(abs(rp));
                else
                    perm_stats(p) = max(rp);
                end
            end
            if opt.twoTailed
                pvals = arrayfun(@(rt) (1 + nnz(perm_stats >= abs(rt))) / (nP+1), r_obs);
            else
                pvals = arrayfun(@(rt) (1 + nnz(perm_stats >= rt)) / (nP+1), r_obs);
            end
        else
            % store full T-by-permutation matrix
            perm_all = nan(nP, T);
            for p = 1:nP
                idx = randperm(N1);
                Xp = reshape(S_neural(idx, idx, :), N1*N1, T);
                Xp = Xp(mask_vec, :);
                rp = corr(Xp, y, 'type', opt.method, 'rows','complete'); % T x 1
                perm_all(p,:) = rp(:).';
            end
            if opt.twoTailed
                pvals = arrayfun(@(t) (1 + nnz(abs(perm_all(:,t)) >= abs(r_obs(t))))/(nP+1), 1:T);
            else
                pvals = arrayfun(@(t) (1 + nnz(perm_all(:,t) >= r_obs(t)))/(nP+1), 1:T);
            end
            perm_stats = perm_all;
        end
    end
end

stats = struct('r',r_obs,'p',pvals,'permDist',perm_stats, ...
    'vecMask',mask,'method',opt.method,'vectorize',opt.vectorize, ...
    'nPerm',nP,'twoTailed',opt.twoTailed,'maxT',logical(opt.maxT));
end
