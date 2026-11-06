function [S, meta] = build_similarity_multivariate(B, varargin)
% BUILD_SIMILARITY_MULTIVARIATE Subject-by-subject similarity from multiple features.
%
%   [S, meta] = movie.build_similarity_multivariate(B, 'Name',Value,...)
%
% INPUT
%   B : [N x P] features (rows=subjects, cols=features).
%       • For numeric methods: numeric matrix or numeric table (auto-converted).
%       • For 'gower': matrix/table/cell with mixed types (numeric, logical, categorical, string).
%
% NAME–VALUE OPTIONS
%   'method'   : 'embedding-corr' (default) | 'embedding-cosine' | ...
%                'euclidean' | 'manhattan' | 'mahalanobis' | 'gower'
%   'return'   : 'similarity' (default) | 'distance'
%   'zscore'   : false (default) – z-score columns (numeric-only methods).
%   'colTypes' : 1xP cell for 'gower' in {'numeric','binary','nominal','ordinal'}.
%                If omitted (and method='gower'), types are inferred (warns once).
%   'simMap'   : 'one-minus' (default) | 'rbf'  (mapping when converting distance→similarity)
%   'rbfSigma' : [] (default) or positive scalar (σ for RBF; [] → median heuristic)
%   'expectSym': true (default) – enforce symmetry & proper diagonal
%
% OUTPUT
%   S    : [N_kept x N_kept] similarity or distance, symmetric; diag=1 (similarity) or 0 (distance).
%   meta : struct with fields:
%          .kept_index, .dropped_n, .N, .P, .method, .return, .zscore, .simMap, .rbfSigma, .colTypes, .notes
%
% NA POLICY
%   • Single policy: listwise deletion. Rows with any missing/undefined are dropped before analysis.

% -------------------- Parse --------------------
ip = inputParser;
ip.addParameter('method','embedding-corr',@(s)ischar(s)||isstring(s));
ip.addParameter('return','similarity',@(s)ischar(s)||isstring(s));
ip.addParameter('zscore',false,@(b)islogical(b)&&isscalar(b));
ip.addParameter('colTypes',[],@(c) isempty(c) || (iscell(c) && isvector(c)));
ip.addParameter('simMap','one-minus',@(s)ischar(s)||isstring(s));
ip.addParameter('rbfSigma',[],@(z) isnumeric(z) && isscalar(z) && (isempty(z) || z>0));
ip.addParameter('expectSym',true,@(b)islogical(b)&&isscalar(b));
ip.parse(varargin{:});
opt = ip.Results;

method  = lower(string(opt.method));
retMode = lower(string(opt.return));
simMap  = lower(string(opt.simMap));

if ~(retMode=="similarity" || retMode=="distance")
    error('behav_similarity_multi:return','return must be "similarity" or "distance".');
end

isNumMethod = any(method == ["embedding-corr","embedding-cosine","euclidean","manhattan","mahalanobis"]);
isGower     = method == "gower";

if ~(ismatrix(B) || istable(B) || iscell(B))
    error('B must be an N×P matrix/table/cell.');
end

% -------------------- Normalize container type wrt method --------------------
if istable(B)
    if isNumMethod
        Bnum = table2array(B);
        if ~isnumeric(Bnum)
            error('Method "%s" requires a numeric N×P input (table must be numeric).', method);
        end
        B = Bnum;
    else % gower
        B = table2cell(B);
    end
else
    if isNumMethod && ~isnumeric(B)
        error('Method "%s" requires a numeric N×P matrix.', method);
    end
    % gower can also accept numeric matrix as-is
end

[~, P] = size(B);  % <-- Correct feature count after normalization

% -------------------- Single NA policy: listwise deletion --------------------
if isNumMethod
    X = double(B);
    okRow = all(isfinite(X), 2);
    kept_idx = find(okRow);
    drop_n   = nnz(~okRow);
    X = X(okRow,:);
    if size(X,1) < 2, error('After NA removal, need at least 2 subjects.'); end
else
    [Bin_cast, okRow, colTypes_used] = prepare_gower_input(B, opt.colTypes);
    kept_idx = find(okRow);
    drop_n   = nnz(~okRow);
    Bin_cast = Bin_cast(okRow,:);
    if size(Bin_cast,1) < 2, error('After NA removal, need at least 2 subjects.'); end
end

% -------------------- Compute core (dis)similarity --------------------
if method == "embedding-corr"
    if opt.zscore, X = zscore_cols(X); end
    S = corrcoef(X.');
    if retMode=="distance", S = 1 - ((S+1)/2); S(1:end+1:end)=0; else, S(1:end+1:end)=1; end

elseif method == "embedding-cosine"
    if opt.zscore, X = zscore_cols(X); end
    nr = sqrt(sum(X.^2,2)); nr(nr==0) = eps;
    Xn = X ./ nr;
    S  = Xn * Xn.';
    if retMode=="distance", S = 1 - ((S+1)/2); S(1:end+1:end)=0; else, S(1:end+1:end)=1; end

elseif method == "euclidean"
    D2 = square_euclidean(X);
    D  = sqrt(max(D2,0));
    S  = finalize_distance(D, retMode, simMap, opt.rbfSigma);

elseif method == "manhattan"
    D  = square_cityblock(X);
    S  = finalize_distance(D, retMode, simMap, opt.rbfSigma);

elseif method == "mahalanobis"
    C    = cov(X);
    Cpin = pinv(C);
    D    = pairwise_mahal(X, Cpin);
    S    = finalize_distance(D, retMode, simMap, opt.rbfSigma);

elseif isGower
    D = gower_distance(Bin_cast, colTypes_used);
    S = finalize_distance(D, retMode, simMap, opt.rbfSigma);

else
    error('Unknown method "%s".', method);
end

% -------------------- Enforce symmetry & diagonal --------------------
if opt.expectSym
    S = 0.5*(S + S.');
    if retMode=="similarity", S(1:end+1:end)=1; else, S(1:end+1:end)=0; end
end

% -------------------- Meta --------------------
meta = struct();
meta.kept_index = kept_idx(:);
meta.dropped_n = drop_n;
meta.N = size(S,1);
meta.P = P;  % <-- Correctly report number of features
meta.method = char(method);
meta.return = char(retMode);
meta.zscore = logical(opt.zscore);
meta.simMap = char(simMap);
meta.rbfSigma = opt.rbfSigma;
if isGower, meta.colTypes = colTypes_used; else, meta.colTypes = []; end
meta.notes = 'Listwise deletion; symmetry & diagonal enforced.';

end
% ===================== Helpers =====================
function Xz = zscore_cols(X)
    mu = mean(X,1);
    sd = std(X,0,1);
    sd(sd==0) = 1;
    Xz = (X - mu) ./ sd;
end

function D2 = square_euclidean(X)
    G   = X*X.';                     
    nrm = sum(X.^2,2);
    D2  = max(0, bsxfun(@plus,nrm, nrm.') - 2*G);
end

function D1 = square_cityblock(X)
    Nloc = size(X,1);
    D1 = zeros(Nloc);
    for i=1:Nloc
        Xi = X(i,:);
        D1(i,i+1:Nloc) = sum(abs(Xi - X(i+1:Nloc,:)), 2).';
    end
    D1 = D1 + D1.';
end

function D = pairwise_mahal(X, Cpinv)
    M  = X * Cpinv;
    q  = sum(M.*X, 2);
    G  = M * X.';
    D2 = bsxfun(@plus,q,q.') - 2*G;
    D2(D2<0) = 0;
    D  = sqrt(D2);
    D(1:end+1:end) = 0;
end

function Sout = finalize_distance(D, ret, map, sigma)
    if ret=="distance"
        Sout = D; Sout(1:end+1:end) = 0; return
    end
    switch map
        case "one-minus"
            denom = max(D(:)); if ~isfinite(denom) || denom<=0, denom = 1; end
            Sout = 1 - D/denom;  Sout(1:end+1:end) = 1;
        case "rbf"
            tri = D(triu(true(size(D)),1)); tri = tri(tri>0);
            if isempty(sigma) || ~(isfinite(sigma) && sigma>0)
                if isempty(tri), sigma = 1; else, sigma = median(tri); if ~isfinite(sigma)||sigma==0, sigma=1; end, end
            end
            Sout = exp(-(D.^2) ./ (2*sigma^2));
            Sout(1:end+1:end) = 1;
        otherwise
            error('Unknown simMap "%s".', map);
    end
end

function [Bin_cast, okRow, colTypes_out] = prepare_gower_input(Bin, colTypes_in)
    Nloc = size(Bin,1);
    Ploc = size(Bin,2);
    if isempty(colTypes_in)
        colTypes_out = infer_coltypes(Bin);
        warnOnce('behav_similarity_multi:colTypes', ...
                 'colTypes inferred for Gower; pass "colTypes" explicitly for reproducibility.');
    else
        if numel(colTypes_in) ~= Ploc
            error('colTypes length (%d) must equal number of columns P (%d).', numel(colTypes_in), Ploc);
        end
        colTypes_out = colTypes_in;
    end

    Bin_cast = cell(Nloc, Ploc);
    okRow = true(Nloc,1);

    for j=1:Ploc
        t   = lower(string(colTypes_out{j}));
        col = Bin(:,j);

        switch t
            case {'numeric','ordinal'}
                if iscell(col), c = cellfun(@double, col); else, c = double(col); end
                Bin_cast(:,j) = num2cell(c);
                okRow = okRow & isfinite(c);

            case 'binary'
                if iscell(col)
                    try
                        b = cellfun(@double, col);
                    catch
                        col = categorical(col);
                        b = double(grp2idx(col))-1;
                    end
                else
                    if islogical(col), b = double(col);
                    elseif isnumeric(col), b = double(col);
                    else, col = categorical(col); b = double(grp2idx(col))-1;
                    end
                end
                Bin_cast(:,j) = num2cell(b);
                okRow = okRow & isfinite(b);

            case 'nominal'
                if ~iscategorical(col)
                    if iscell(col) || isstring(col)
                        col = categorical(col);
                    else
                        col = categorical(string(col));
                    end
                end
                Bin_cast(:,j) = cellstr(string(col));
                okRow = okRow & ~isundefined(col);

            otherwise
                error('Unknown colTypes{%d}="%s".', j, t);
        end
    end
end

function D = gower_distance(Bin_cast, types)
    Nloc = size(Bin_cast,1);
    Ploc = size(Bin_cast,2);
    D = zeros(Nloc);
    for j=1:Ploc
        t = lower(string(types{j}));
        if any(strcmp(t, {'numeric','ordinal'}))
            c = cellfun(@double, Bin_cast(:,j));
            mn = min(c); mx = max(c); rng = mx - mn; if rng==0, rng=1; end
            c01 = (c - mn)/rng;
            Dij = abs(c01 - c01.');
        elseif strcmp(t,'binary')
            b = cellfun(@double, Bin_cast(:,j));
            Dij = abs(b - b.');
        elseif strcmp(t,'nominal')
            s = string(Bin_cast(:,j));
            Dij = double(s ~= s.');
        else
            error('Unknown colTypes entry: "%s".', t);
        end
        D = D + Dij;
    end
    if Ploc > 0, D = D / Ploc; end
    D(1:Nloc+1:end) = 0;
end

function types = infer_coltypes(Bin)
    Ploc = size(Bin,2);
    types = cell(1,Ploc);
    for j=1:Ploc
        col = Bin(:,j);
        if iscell(col)
            k = find(~cellfun(@isempty,col),1);
            if isempty(k), types{j} = 'nominal'; continue; end
            v = col{k};
            if islogical(v), types{j} = 'binary';
            elseif isnumeric(v)
                u = unique(cellfun(@double, col(~cellfun(@isempty,col))));
                if numel(u)<=7, types{j}='ordinal'; else, types{j}='numeric'; end
            elseif isstring(v) || ischar(v) || iscategorical(v)
                types{j} = 'nominal';
            else
                types{j} = 'nominal';
            end
        else
            if islogical(col), types{j}='binary';
            elseif isnumeric(col)
                u = unique(col(~isnan(col)));
                if numel(u)<=7, types{j}='ordinal'; else, types{j}='numeric'; end
            elseif isstring(col) || iscategorical(col)
                types{j}='nominal';
            else
                types{j}='nominal';
            end
        end
    end
end

function warnOnce(id,msg)
   persistent SEEN;
    if isempty(SEEN)
        SEEN = containers.Map('KeyType','char','ValueType','logical');
    end
    kid = char(id);
    if ~isKey(SEEN, kid)
        warning(kid, '%s', msg);
        SEEN(kid) = true;
    end

end
