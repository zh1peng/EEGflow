function [S, meta] = build_similarity_univariate(B, varargin)
% BUILD_SIMILARITY_UNIVARIATE  Univariate behavioral similarity for IS-RSA / MRQAP.
%
%   This function takes a single behavioral variable (vector) and constructs an
%   N×N subject-by-subject similarity matrix S in [0,1] based on various
%   univariate models. It is intended as a building block for IS-RSA, MRQAP,
%   and other dyadic analyses.
%
%   It supports:
%       - numeric / ordinal variables (Anna Karenina, absdiff/RBF, etc.)
%       - binary variables (0/1 or logical)
%       - nominal variables (categorical/string/cellstr)
%
% INPUT
%   B           [N×1] vector
%               Univariate behavioral data for N subjects. Can be:
%                   * numeric / ordinal
%                   * logical or 0/1 (binary)
%                   * categorical / string / cellstr (nominal)
%
% OPTIONAL NAME-VALUE PAIRS
%
%   'uniModel'  (string) Univariate similarity model.
%
%       For NUMERIC / ORDINAL:
%           Abs-diff / NN family (single implementation):
%               'absdiff'
%               'nn'                      (alias; for clarity in code/papers)
%               'nearest-neighbor'
%               'nn-absdiff'
%               'rank-absdiff'
%
%           All of these do the same math:
%               - Compute absolute differences on either:
%                   • raw values      (rank = false), or
%                   • ranks           (rank = true, or 'rank-absdiff')
%               - Then convert to similarity:
%                     S_ij = 1 - D_ij / max(D(:))
%                 (if max(D) == 0 → S = ones(N))
%
%           RBF / Gaussian kernel on absolute difference:
%               'rbf'
%               'gaussian'
%               (operates on ranks if rank = true, raw if rank = false)
%               S_ij = exp( - (D_ij^2) / (2 * sigma^2) )
%
%           Anna Karenina family (using 0–1 scaled ranks r01):
%           Let r01 in [0,1], higher = “worse” / higher severity.
%
%           High-end similarity (pairs both high):
%               'annak-min'
%                   S_ij = min(r01_i, r01_j)
%               'annak-mean'
%                   S_ij = (r01_i + r01_j) / 2
%               'annak-mean*min'
%               'annak-mean-min'
%               'annak-prod'
%                   S_ij = mean(r01_i,r01_j) * min(r01_i,r01_j)
%
%           Low-end similarity (pairs both low; complements):
%               'div-annak-min'
%                   S_ij = 1 - min(r01_i, r01_j)
%               'div-annak-mean'
%                   S_ij = 1 - (r01_i + r01_j)/2
%               'div-annak-mean*min'
%               'div-annak-mean-min'
%               'div-annak-prod'
%                   meanMat = (r01_i + r01_j)/2
%                   minMat  = min(r01_i, r01_j)
%                   S_ij    = 1 - (meanMat .* minMat)
%
%           NOTE: Underscores are allowed and internally mapped to hyphens,
%                 e.g. 'annak_min' → 'annak-min',
%                       'div_annak_mean*min' → 'div-annak-mean*min'.
%
%       For BINARY (0/1 or logical):
%           'same'
%               S_ij = 1 if B_i == B_j, else 0
%           Any other uniModel:
%               Uses Hamming-based similarity:
%                   D_ij = |B_i - B_j|
%                   S_ij = 1 - D_ij
%
%       For NOMINAL (categorical/string/cellstr):
%           Ignores uniModel, uses:
%               S_ij = 1 if category_i == category_j, else 0
%
%   'rank'      true / false
%               For numeric / ordinal variables, this controls whether values
%               are rank-transformed before computing similarity for
%               'absdiff'/'nn' and 'rbf'.
%
%               Default: true.
%
%   'rbfSigma'  [] or positive scalar
%               For 'rbf'/'gaussian' models:
%                   []      → auto sigma via median heuristic on upper triangle.
%                   >0      → use this sigma directly.
%
% OUTPUT
%   S           [N×N] similarity matrix in [0,1].
%               Symmetric, with diagonal set to 1.
%
%   meta        struct with fields:
%                   .N        = number of subjects
%                   .P        = 1 (univariate)
%                   .mode     = 'univariate'
%                   .uniModel = uniModel as provided by user (char)
%
% NOTES
%   - NaNs in B propagate into S (no pairwise deletion inside).
%   - For AnnaK models, 'rank' is ignored; they always use rank-based r01.

% -------------------------------------------------------------------------
% Parse options
% -------------------------------------------------------------------------
ip = inputParser;
ip.addParameter('uniModel','nn', ...
    @(x) ischar(x) || isstring(x));
ip.addParameter('rank',true, ...
    @(x) islogical(x) && isscalar(x));
ip.addParameter('rbfSigma',[], ...
    @(x) isempty(x) || (isnumeric(x) && isscalar(x) && isfinite(x) && x>0));
ip.parse(varargin{:});
opt = ip.Results;

assert(isvector(B),'build_similarity_univariate: Provide a univariate vector B.');
x = B(:);

% -------------------------------------------------------------------------
% Type dispatch: binary / nominal / numeric
% -------------------------------------------------------------------------
if islogical(x) || (isnumeric(x) && all(ismember(x(~isnan(x)),[0 1])))
    dtype = 'binary';
elseif iscategorical(x) || isstring(x) || iscellstr(x)
    if ~iscategorical(x), x = categorical(x); end
    dtype = 'nominal';
else
    dtype = 'numeric';
end

N = numel(x);
S = nan(N);

% -------------------------------------------------------------------------
% Main switch by data type
% -------------------------------------------------------------------------
switch dtype
    % ---------------------------------------------------------------------
    % BINARY: logical or numeric 0/1
    % ---------------------------------------------------------------------
    case 'binary'
        xb = double(x);
        if any(strcmpi(opt.uniModel, {'same'}))
            % Pure same/different similarity
            S = double(xb == xb.');
        else
            % Hamming-based similarity: S = 1 - |x_i - x_j|
            D = abs(xb - xb.');
            S = 1 - D;
        end

    % ---------------------------------------------------------------------
    % NOMINAL: categorical / string / cellstr
    % ---------------------------------------------------------------------
    case 'nominal'
        S = double(x == x.');

    % ---------------------------------------------------------------------
    % NUMERIC / ORDINAL
    % ---------------------------------------------------------------------
    otherwise
        % Normalize model name: lower + '_' → '-'
        m = lower(string(opt.uniModel));
        m = replace(m,'_','-');

        switch m
            % ------------------------------
            % Abs-diff / NN family
            % ------------------------------
            case {'nn','nearest-neighbor','nn-absdiff','absdiff'}
                if opt.rank
                    z = tiedrank(x);
                else
                    z = x;
                end
                D = abs(z - z.');
                maxD = max(D(:));
                if maxD <= eps
                    S = ones(N);   % all identical → similarity = 1
                    warning('build_similarity_univariate: All similarity values are identical.');
                else
                    S = 1 - D ./ maxD;
                end

            % ------------------------------
            % RBF / Gaussian kernel
            % ------------------------------
            case {'rbf','gaussian'}
                if opt.rank
                    z = tiedrank(x);
                else
                    z = x;
                end
                D = abs(z - z.');
                if isempty(opt.rbfSigma)
                    tri = D(triu(true(N),1));
                    sig = median(tri(tri>0));
                    if isempty(sig) || ~isfinite(sig) || sig==0, sig = 1; end
                else
                    sig = opt.rbfSigma;
                end
                S = exp(-(D.^2) ./ (2*(sig^2)));

            % ------------------------------
            % Anna Karenina family (numeric)
            % always uses ranks → r01 in [0,1]
            % ------------------------------
            case {'annak-min','annak-mean', ...
                  'annak-mean*min','annak-mean-min','annak-prod', ...
                  'div-annak-min','div-annak-mean', ...
                  'div-annak-mean*min','div-annak-mean-min','div-annak-prod'}

                r  = tiedrank(x);
                if N == 1
                    r01 = 1;
                else
                    r01 = (r-1)/(N-1);  % 0–1
                end
                r01_i = r01;
                r01_j = r01';

                minMat  = min(r01_i, r01_j);
                meanMat = (r01_i + r01_j) / 2;
                prodMat = meanMat .* minMat;

                switch m
                    case 'annak-min'
                        S = minMat;
                    case 'annak-mean'
                        S = meanMat;
                    case {'annak-mean*min','annak-mean-min','annak-prod'}
                        S = prodMat;
                    case 'div-annak-min'
                        S = 1 - minMat;
                    case 'div-annak-mean'
                        S = 1 - meanMat;
                    case {'div-annak-mean*min','div-annak-mean-min','div-annak-prod'}
                        S = 1 - prodMat;
                end

            otherwise
                error('build_similarity_univariate: Unknown uniModel "%s".', opt.uniModel);
        end
end

% -------------------------------------------------------------------------
% Enforce symmetry and set diagonal
% -------------------------------------------------------------------------
S = 0.5*(S + S.');      % numerical symmetry
S(1:N+1:end) = 1;       % force diagonal to 1 (max similarity)

% -------------------------------------------------------------------------
% Meta information
% -------------------------------------------------------------------------
meta = struct('N',N, ...
              'P',1, ...
              'mode','univariate', ...
              'uniModel',char(opt.uniModel));
end
