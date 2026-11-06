function [Y, ax] = plot_similarity_embedding(S, varargin)
% PLOT_SIMILARITY_EMBEDDING  Visualize a subject×subject similarity matrix with t-SNE/MDS/Spectral.
%
%   [Y, ax] = plot_similarity_embedding(S, 'Name', Value, ...)
%
% INPUT
%   S : [N x N] similarity matrix (symmetric; larger = more similar). Diagonal can be 1.
%
% NAME-VALUE OPTIONS
%   'method'       : 'tsne' (default) | 'mds' | 'spectral'
%   'dims'         : 2 (default) | 3
%   'distFrom'     : 'oneMinus' (default) | 'sqrtOneMinus'   % S -> D conversion
%   'perplexity'   : 30            % t-SNE perplexity
%   'seed'         : [] or integer % RNG seed for reproducibility
%   'init'         : 'pca' (default) | 'mds' | 'random'
%                    - Only used for t-SNE. 'pca' uses PCA of pre-embed; 'mds' uses first dims of pre-embed.
%   'numIterations': []            % t-SNE NumIterations (leave [] for MATLAB default)
%   'preembedDim'  : 50            % intermediate dimension for t-SNE (classical MDS on distances)
%   'labels'       : {} cellstr of length N
%   'groups'       : [] numeric/categorical vector (length N) for colors
%   'title'        : '' 
%   'markerSize'   : 60
%   'labelAlpha'   : 0.8
%
% OUTPUT
%   Y  : [N x dims] embedding coordinates
%   ax : axes handle
%
% NOTES
%   - For t-SNE, we first do classical MDS to a Euclidean feature space (q=preembedDim, <= N-1),
%     then run t-SNE on those features. This avoids the 'Distance','precomputed' limitation.
%   - For reviewer-proof figures, consider MDS or Spectral (deterministic) in the paper.
%
% v1.2 (deterministic t-SNE via seed + init; preembedDim option)
%
%EXAMPLES
% Deterministic t-SNE (seed + PCA init on MDS pre-embed, 50D):
% [Y_tsne, ax] = movie.plot_similarity_embedding(ISCpair, ...
%     'method','tsne', 'perplexity',30, ...
%     'seed',42, 'init','pca', 'preembedDim',50, ...
%     'title','Neural ISC: t-SNE (seeded + PCA init)');

% Deterministic MDS:
% [Y_mds, ax] = movie.plot_similarity_embedding(S_behav, ...
%     'method','mds', 'dims',2, ...
%     'title','Behavior: MDS (deterministic)');

% Spectral embedding:
% [Y_spec, ax] = movie.plot_similarity_embedding(ISCpair, ...
%     'method','spectral', 'title','Neural ISC: Spectral');


% ---------- parse ----------
ip = inputParser;
ip.addParameter('method','tsne');
ip.addParameter('dims',2, @(x)isnumeric(x) && ismember(x,[2 3]));
ip.addParameter('distFrom','oneMinus');
ip.addParameter('perplexity',30, @(x)isnumeric(x)&&isscalar(x)&&x>0);
ip.addParameter('seed',[]);
ip.addParameter('init','pca');                       % 'pca' | 'mds' | 'random'
ip.addParameter('numIterations',[],@(x) isempty(x) || (isscalar(x) && x>0));
ip.addParameter('preembedDim',50,@(x)isnumeric(x)&&isscalar(x)&&x>=2);
ip.addParameter('labels',{});
ip.addParameter('groups',[]);
ip.addParameter('title','');
ip.addParameter('markerSize',60,@(x)isnumeric(x)&&isscalar(x)&&x>0);
ip.addParameter('labelAlpha',0.8,@(x)isnumeric(x)&&isscalar(x)&&x>=0&&x<=1);
ip.parse(varargin{:});
opt = ip.Results;

S = double(S);
N = size(S,1);
assert(ismatrix(S) && N==size(S,2), 'S must be square.');
if ~issymmetric_safe(S)
    warning('plot_similarity_embedding:nonSym', 'S is not symmetric; symmetrizing.');
    S = (S + S.')/2;
end

% ---------- RNG ----------
if ~isempty(opt.seed), rng(opt.seed); end

method = lower(string(opt.method));
dims   = opt.dims;

switch method
    case "tsne"
        % --- Similarity -> Distance ---
        D = sim2dist(S, opt.distFrom);

        % --- Pre-embed distances via classical MDS to Euclidean space ---
        q = min([max(3, dims+2), opt.preembedDim, N-1]);  % reasonable intermediate dim
        try
            [Z, ~] = cmdscale(D, q);
        catch
            % small jitter if non-Euclidean issues
            Dj = D + 1e-8*randn(size(D));
            [Z, ~] = cmdscale(Dj, q);
        end

        % --- Deterministic initialization for t-SNE ---
        initY = [];
        switch lower(string(opt.init))
            case "pca"
                % PCA on Z to get a stable low-d init
                try
                    [~, score] = pca(Z, 'NumComponents', dims);
                    initY = score(:,1:dims);
                catch
                    % Fall back to using first dims directly
                    initY = Z(:,1:dims);
                end
            case "mds"
                % Use first dims of pre-embed (already Euclidean)
                initY = Z(:,1:dims);
            case "random"
                % leave initY empty for random init (not recommended for reproducibility)
            otherwise
                error('plot_similarity_embedding:init','Unknown init option "%s".', opt.init);
        end

        % --- Build t-SNE args (on features Z) ---
        tsneArgs = {'NumDimensions', dims, ...
                    'Perplexity',   opt.perplexity, ...
                    'Standardize',  false, ...
                    'Distance',     'euclidean'};
        if ~isempty(initY),      tsneArgs = [tsneArgs, {'InitialY', initY}]; end
        if ~isempty(opt.numIterations)
            tsneArgs = [tsneArgs, {'NumIterations', opt.numIterations}];
        end

        % --- Run t-SNE (prefer barneshut if available) ---
        try
            Y = tsne(Z, 'Algorithm','barneshut', tsneArgs{:});
        catch
            Y = tsne(Z, tsneArgs{:}); % fallback
        end

    case "mds"
        D = sim2dist(S, opt.distFrom);
        try
            [Y, ~] = cmdscale(D, dims);
        catch
            Dj = D + 1e-8*randn(size(D));
            [Y, ~] = cmdscale(Dj, dims);
        end

    case "spectral"
        % Laplacian eigenmaps
        W = S;
        W(isnan(W)) = 0;
        W(W<0) = 0;
        W(1:N+1:end) = 0;
        W = (W + W.')/2;
        d  = sum(W,2);
        L  = diag(d) - W;                 % unnormalized Laplacian
        [V,E] = eig((L+L')/2, 'vector');  %#ok<ASGLU>
        [~, idx] = sort(E, 'ascend');
        if numel(idx) < dims+1
            Y = zeros(N, dims);
        else
            Y = V(:, idx(2:dims+1));
        end

    otherwise
        error('Unknown method: %s', method);
end

% ---------- plotting ----------
ax = gca; hold(ax,'on');
use3d = (dims == 3);

% Group coloring
g = opt.groups;
if isempty(g)
    if use3d
        scatter3(Y(:,1), Y(:,2), Y(:,3), opt.markerSize, 'filled');
    else
        scatter(Y(:,1), Y(:,2), opt.markerSize, 'filled');
    end
else
    [gcat,~,gid] = unique(categorical(g));
    cmap = lines(numel(gcat));
    for k = 1:numel(gcat)
        ii = (gid==k);
        if use3d
            scatter3(Y(ii,1), Y(ii,2), Y(ii,3), opt.markerSize, 'filled', ...
                     'MarkerFaceColor', cmap(k,:));
        else
            scatter(Y(ii,1), Y(ii,2), opt.markerSize, 'filled', ...
                    'MarkerFaceColor', cmap(k,:));
        end
    end
    legend(string(gcat), 'Location','bestoutside');
end

% Labels
if ~isempty(opt.labels)
    labs = opt.labels;
    if numel(labs) ~= N
        warning('labels length != N; ignoring labels'); 
        labs = {};
    end
    if ~isempty(labs)
        if use3d
            for i=1:N
                text(Y(i,1), Y(i,2), Y(i,3), [' ',char(labs{i})], ...
                     'FontSize',9, 'Color',[0 0 0 opt.labelAlpha]);
            end
        else
            for i=1:N
                text(Y(i,1), Y(i,2), [' ',char(labs{i})], ...
                     'FontSize',9, 'Color',[0 0 0 opt.labelAlpha]);
            end
        end
    end
end

grid on; box on;
if ~isempty(opt.title), title(opt.title); end
if use3d, view(3); rotate3d on; end
axis tight; hold(ax,'off');

end % function

% ---------- helpers ----------
function tf = issymmetric_safe(A)
tf = isequaln(A, A.');
end

function D = sim2dist(S, how)
switch lower(string(how))
    case "oneminus"
        D = 1 - S;
        D = max(0, min(1, D));
    case "sqroneminus"
        D = sqrt(max(0, 1 - S));
    otherwise
        error('sim2dist: unknown distFrom "%s"', how);
end
N = size(D,1);
D(1:N+1:end) = 0;
D = (D + D.')/2;
end
