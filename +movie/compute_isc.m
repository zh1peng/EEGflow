function [ISC, meta, ISCpair] = compute_isc(Y, varargin)
% COMPUTE_ISC  Inter-subject similarity (2-D only): per-subject LOSO-ISC and pairwise S×S.
%
%   [ISC, meta] = compute_isc(Y, ...)
%   [ISC, meta, ISCpair] = compute_isc(Y, ...)
%
% INPUT
%   Y : [T x N]  (time x subjects). 2-D only. If you have 3-D (T x D x N),
%       collapse/choose components externally (e.g., average across D) to get T x N.
%
% NAME-VALUE OPTIONS (all optional)
%   'timeResolved' : logical (default: false)
%       If true, compute time-resolved ISC with a sliding window.
%   'winLength'    : positive integer (default: [])
%       Window length (samples) for time-resolved ISC. Required if timeResolved=true.
%       If even is given, it will be incremented by 1 for symmetry.
%   'edgeMode'     : 'replicate' (default) | 'reflect' | 'shrink'
%       Edge handling for time-resolved mode.
%           shrink    = “don’t invent data; accept shorter windows near edges”
%           reflect   = “invent data by mirroring the signal”
%           replicate = “invent data by holding the edge value constant”
%   'pairMetric'   : 'corr' (default) | 'cov'
%       Subject-by-subject similarity metric used **consistently** for LOSO-ISC and ISCpair.
%   'fisherZ'      : logical (default: true)
%       If true and pairMetric='corr', apply Fisher z-transform **to ISCpair only**.
%   'pairwise'     : logical (default: false)
%       If true and timeResolved=true, compute ISCpair over time.
%   'step'         : positive integer (default: 1)
%       Step size (samples) between successive window centers in time-resolved mode.
%   'overlap'      : scalar in [0,1) or [] (default: [])
%       If non-empty, overrides 'step' as:
%           step = max(1, floor(winLength * (1 - overlap))).
%
% OUTPUTS
%   ISC     : If timeResolved=false -> [N x 1]
%             If timeResolved=true  -> [N x T]  when step=1 & overlap=[]
%                                          [N x nCenter] otherwise
%   meta    : struct with fields:
%               .T, .N, .timeResolved, .winLength, .edgeMode,
%               .pairMetric, .fisherZ, .pairwiseComputed,
%               .step, .overlap, .centerIdx
%   ISCpair : If timeResolved=false -> [N x N]
%             If timeResolved=true  -> [N x N x T] or [N x N x nCenter] (matches ISC)
%
% v2.3 – add step/overlap, compressed time when step>1/overlap used.

% ---------- Validate input ----------
if ndims(Y) ~= 2
    error('compute_isc:2Donly', ...
        'Y must be 2-D [T x N]. If 3-D, collapse to 2-D before calling.');
end
[T, N] = size(Y);

% ---------- Parse options ----------
P = inputParser;
P.addParameter('timeResolved', false, @(x)islogical(x)&&isscalar(x));
P.addParameter('winLength',    [],    @(x)isempty(x) || (isscalar(x) && x>=2 && x==floor(x)));
P.addParameter('edgeMode',     'replicate', @(s)ischar(s) || isstring(s));
P.addParameter('pairMetric',   'corr', @(s) any(strcmpi(string(s),["corr","cov"])));
P.addParameter('fisherZ',      true, @(x)islogical(x)&&isscalar(x));
P.addParameter('pairwise',     false, @(x) isempty(x) || (islogical(x) && isscalar(x)));
P.addParameter('step',         1, @(x)isscalar(x) && x>=1 && x==floor(x));
P.addParameter('overlap',      [], @(x)isempty(x) || (isscalar(x) && x>=0 && x<1));
P.parse(varargin{:});
opt = P.Results;

opt.edgeMode   = lower(string(opt.edgeMode));
opt.pairMetric = lower(string(opt.pairMetric));

% Decide whether to compute pairwise matrices
wantPair = opt.pairwise && (nargout >= 3);
% If pairwise + time-resolved -> overlap is required
if wantPair && opt.timeResolved && isempty(opt.overlap)
    error('compute_isc:overlapRequired', ...
        'Overlap must be specified when computing pairwise matrices in time-resolved mode.');
end

meta = struct('T',T,'N',N, ...
              'timeResolved',logical(opt.timeResolved), ...
              'winLength',opt.winLength, ...
              'edgeMode',char(opt.edgeMode), ...
              'pairMetric',char(opt.pairMetric), ...
              'fisherZ',logical(opt.fisherZ), ...
              'pairwiseComputed',logical(wantPair), ...
              'step',[], ...
              'overlap',[], ...
              'centerIdx',[]);

% ---------- Static branch ----------
if ~opt.timeResolved
    C = safe_gram(Y, opt.pairMetric);   % N x N
    ISC = isc_from_C(C);                % N x 1

    if wantPair
        ISCpair = C;
        if opt.fisherZ && opt.pairMetric == "corr"
            ISCpair = atanh(max(min(ISCpair, 0.999999), -0.999999));
        end
    else
        ISCpair = [];
    end
    return;
end

% ---------- Time-resolved branch ----------
if isempty(opt.winLength)
    error('compute_isc:winLengthRequired', ...
          'When timeResolved=true, you must provide ''winLength'' (>=2).');
end
w = opt.winLength;
if mod(w,2)==0
    warning('compute_isc:evenWindow', ...
        'winLength=%d is even; incremented to %d for symmetric centering.', w, w+1);
    w = w + 1;
end
h = floor((w-1)/2);

% Determine step from overlap or step parameter
if ~isempty(opt.overlap)
    if opt.overlap < 0 || opt.overlap >= 1
        error('compute_isc:badOverlap', ...
            'overlap must be in [0,1). Got %.3f.', opt.overlap);
    end
    step = max(1, floor(w * (1 - opt.overlap)));
else
    step = opt.step;
end
step = max(1, step);

% Centers on original time axis
centerIdx = 1:step:T;
nCenter   = numel(centerIdx);

meta.winLength = w;
meta.step      = step;
meta.overlap   = opt.overlap;
meta.centerIdx = centerIdx(:).';

% Decide output time dimension:
%   if step==1 and no overlap was requested -> keep legacy [N x T]
%   else -> compressed [N x nCenter]
useCompressed = ~(step == 1 && isempty(opt.overlap));

if useCompressed
    ISC = nan(N, nCenter, 'like', Y);
    if wantPair
        ISCpair = nan(N, N, nCenter, 'like', Y);
    else
        ISCpair = [];
    end
else
    ISC = nan(N, T, 'like', Y);
    if wantPair
        ISCpair = nan(N, N, T, 'like', Y);
    else
        ISCpair = [];
    end
end

% ---------- Sliding window ----------
switch opt.edgeMode
    case "shrink"
        for k = 1:nCenter
            t  = centerIdx(k);
            t1 = max(1, t - h);
            t2 = min(T, t + (w-1 - (t - t1)));
            W  = Y(t1:t2, :);
            if size(W,1) < 2, continue; end

            C = safe_gram(W, opt.pairMetric);
            if useCompressed
                ISC(:, k) = isc_from_C(C);
            else
                ISC(:, t) = isc_from_C(C);
            end

            if wantPair
                P = C;
                if opt.fisherZ && opt.pairMetric == "corr"
                    P = atanh(max(min(P, 0.999999), -0.999999));
                end
                if useCompressed
                    ISCpair(:,:,k) = P;
                else
                    ISCpair(:,:,t) = P;
                end
            end
        end

    case {"reflect","replicate"}
        Ypad = pad_time(Y, h, opt.edgeMode);  % [T+2h x N]
        for k = 1:nCenter
            t   = centerIdx(k);
            idx = t:(t+w-1);
            W   = Ypad(idx, :);
            C   = safe_gram(W, opt.pairMetric);

            if useCompressed
                ISC(:, k) = isc_from_C(C);
            else
                ISC(:, t) = isc_from_C(C);
            end

            if wantPair
                P = C;
                if opt.fisherZ && opt.pairMetric == "corr"
                    P = atanh(max(min(P, 0.999999), -0.999999));
                end
                if useCompressed
                    ISCpair(:,:,k) = P;
                else
                    ISCpair(:,:,t) = P;
                end
            end
        end

    otherwise
        error('compute_isc:edgeMode', 'Unknown edgeMode: %s', opt.edgeMode);
end

end % compute_isc


% ==================== Helpers ====================

function C = safe_gram(W, metric)
if size(W,1) < 2
    C = nan(size(W,2));
    return;
end
switch string(metric)
    case "corr"
        C = corrcoef(W);
    case "cov"
        C = cov(W);
    otherwise
        error('safe_gram:metric','Unknown pairMetric: %s', metric);
end
end

function isc_vec = isc_from_C(C)
N = size(C,1);
diagC = diag(C);
sumOff = sum(C,2) - diagC;
sumDiagOthers = sum(diagC) - diagC;
Rb = 2 .* sumOff;
Rw = (N-1).*diagC + sumDiagOthers;
isc_vec = Rb ./ (Rw + eps);
end

function Ypad = pad_time(Y, h, mode)
[T, ~] = size(Y);
if h <= 0, Ypad = Y; return; end
switch string(mode)
    case "reflect"
        hL = min(h, T-1);
        hR = min(h, T-1);
        left  = Y(hL:-1:1, :);
        right = Y(T:-1:(T-hR+1), :);
        Ypad  = [left; Y; right];
    case "replicate"
        left  = repmat(Y(1,:), [h, 1]);
        right = repmat(Y(end,:), [h, 1]);
        Ypad  = [left; Y; right];
    otherwise
        error('pad_time:mode','Unknown pad mode: %s', mode);
end
end
