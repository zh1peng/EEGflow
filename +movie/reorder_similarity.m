function order = reorder_similarity(S, varargin)
% REORDER_SIMILARITY  Find a visualization-friendly subject order.
%
%   order = reorder_similarity(S, 'Name',Value,...)
%
% INPUT
%   S : [N x N] similarity (symmetric).
%
% NAME-VALUE
%   'method'   : 'hier' (default) | 'spectral' | 'identity' | 'given'
%   'linkage'  : 'average' (default) | 'single' | 'complete' | ...
%   'given'    : permutation 1:N (used when method='given')
%
% OUTPUT
%   order : [1 x N] permutation indices.
%
% NOTE
%   Use this only for plotting; keep analysis on the **unsorted** matrices.

ip = inputParser;
ip.addParameter('method','hier');
ip.addParameter('linkage','average');
ip.addParameter('given',[]);
ip.parse(varargin{:});
opt = ip.Results;

N = size(S,1);
switch lower(string(opt.method))
    case "identity"
        order = 1:N;
    case "given"
        g = opt.given(:).'; 
        assert(numel(g)==N && all(sort(g)==1:N),'given must be a permutation of 1:N');
        order = g;
    case "hier"
        D = 1 - S; D = max(0,min(1,D));        % distance from similarity
        D(isnan(D)) = nanmedian(D(:));
        Y = squareform(D,'tovector');
        Z = linkage(Y, opt.linkage);
        order = optimalleaforder(Z, Y);
    case "spectral"
        W = S; W(isnan(W))=0; W=(W+W')/2; W(1:N+1:end)=0;
        d = sum(W,2); L = diag(d)-W;
        [V,E] = eig((L+L')/2,'vector'); [~,idx]=sort(E,'ascend');
        if numel(idx)<2, order=1:N; else, [~,order]=sort(V(:,idx(2)),'ascend'); end
        order = order(:).';
    otherwise
        error('Unknown method');
end
end
