function h = plot_isc_test(out, varargin)
% PLOT_ISC_TEST  Publication-ready visualizations for test_isc results.
%
% USAGE
%   h = plot_isc_test(out);                                % auto mode
%   h = plot_isc_test(out, 'mode','maxT');                 % choose an inference overlay
%   h = plot_isc_test(out, 'time', t, 'minRun', round(1.0*Fs));
%   h = plot_isc_test(out, 'mode','all', 'savePath','figs/isc_plot.pdf');
%
% INPUT
%   out : struct produced by test_isc(...)
%
% OPTIONS (name-value)
%   'mode'        : 'auto' (default) | 'pointwise' | 'maxT' | 'cluster' | 'tfce' | 'all'
%                   - auto: static => null histogram; time-resolved => group trace + pointwise band + all significant overlays
%   'time'        : [1 x T] time axis (e.g., seconds). Default: 1:T
%   'minRun'      : non-negative integer (default: 0). Minimum contiguous run to display as significant (in samples).
%   'showPointwiseBand' : logical (default: true). Show uncorrected 95% band when time-resolved (for context).
%   'title'       : char/string. Default auto.
%   'yLabel'      : char/string. Default: 'Group ISC (r)' when pairMetric='corr' else 'Group ISC'.
%   'lineWidth'   : numeric (default: 1.6). Group curve width.
%   'fontSize'    : numeric (default: 12). Base font size.
%   'savePath'    : char/string (default: ''). If non-empty, saves figure via exportgraphics.
%   'colors'      : struct with fields:
%                   .curve, .band, .pointwise, .maxT, .cluster, .tfce
%                   (each is an RGB triplet). Defaults chosen for contrast.
%
% OUTPUT
%   h : struct of handles (figure, axes, lines, patches)
%
% Notes
%   • For static results: shows null distribution (hist + KDE) with observed value and annotation of p's (if available).
%   • For time-resolved: plots group ISC curve; optional uncorrected 95% band; overlays significant spans for the chosen mode(s).
%   • minRun only affects visualization (mask shortening), not inference results.
%
% (c) 2025 – tailored for EEGdojo/ISC visualization.

% ---------- Parse options ----------
P = inputParser;
P.addParameter('mode','auto', @(s) any(strcmpi(string(s),["auto","pointwise","maxT","cluster","tfce","all"])));
P.addParameter('time', [], @(x)isnumeric(x) && isvector(x));
P.addParameter('minRun', 0, @(x)isnumeric(x)&&isscalar(x)&&x>=0);
P.addParameter('showPointwiseBand', true, @(x)islogical(x)&&isscalar(x));
P.addParameter('title', '', @(s)ischar(s) || isstring(s));
P.addParameter('yLabel','', @(s)ischar(s) || isstring(s));
P.addParameter('lineWidth', 1.6, @(x)isnumeric(x)&&isscalar(x)&&x>0);
P.addParameter('fontSize', 12, @(x)isnumeric(x)&&isscalar(x)&&x>0);
P.addParameter('savePath','', @(s)ischar(s) || isstring(s));

% default colors (friendly, high-contrast)
C.curve    = [0.10 0.30 0.75];
C.band     = [0.75 0.85 1.00];   % fill
C.pointwise= [0.25 0.60 0.25];   % green
C.maxT     = [0.80 0.20 0.20];   % red
C.cluster  = [0.85 0.55 0.10];   % orange
C.tfce     = [0.50 0.20 0.70];   % purple
P.addParameter('colors', C, @(s)isstruct(s));

P.parse(varargin{:});
opt = P.Results;
C = opt.colors;

% ---------- Inspect 'out' ----------
isTime = isfield(out.meta,'timeResolved') && out.meta.timeResolved;
pairMetric = string(out.meta.pairMetric);
alpha = out.meta.alpha;
group = out.obs.group(:)';    % 1 x T or scalar
T = numel(group);
if isempty(opt.time), t = 1:T; else, t = opt.time(:)'; end
if numel(t) ~= T
    error('plot_isc_test:timeLength','Length of ''time'' (%d) must match number of samples (%d).', numel(t), T);
end

% auto labels
if strlength(opt.yLabel)==0
    if strcmpi(pairMetric,'corr')
        ylab = 'Group ISC (r)';
    else
        ylab = 'Group ISC';
    end
else
    ylab = char(opt.yLabel);
end
if strlength(opt.title)==0
    ttl = sprintf('ISC %s', tern(isTime,'(time-resolved)','(static)'));
else
    ttl = char(opt.title);
end

% decide modes to show
mode = lower(string(opt.mode));
if mode=="auto"
    if isTime, modeList = ["pointwise","maxT","cluster","tfce"];  % show all overlays
    else,      modeList = "static";
    end
elseif mode=="all"
    if isTime, modeList = ["pointwise","maxT","cluster","tfce"];
    else,      modeList = "static";
    end
elseif ~isTime && mode~="static"
    % for static, we always do histogram view regardless of requested infer mode
    modeList = "static";
else
    modeList = mode;  % one of pointwise/maxT/cluster/tfce
end

% ---------- Create figure ----------
h.fig = figure('Color','w','Name','plot_isc_test'); 
h.ax  = axes('Parent',h.fig); hold(h.ax,'on'); box(h.ax,'on'); grid(h.ax,'on');

set(h.ax,'FontSize',opt.fontSize);

if ~isTime
    % ====================== STATIC VIEW ======================
    % Null distribution
    null = out.null.group(:);
    obs  = group;
    % histogram
    nb = max(20, round(sqrt(numel(null))));
    h.hist = histogram(h.ax, null, nb, 'Normalization','pdf', 'FaceColor',[0.85 0.85 0.85], 'EdgeColor',[0.5 0.5 0.5]);
    % kernel density estimate (ksdensity works on double)
    try
        [f, xi] = ksdensity(double(null),'Function','pdf');
        h.kde = plot(h.ax, xi, f, 'k-', 'LineWidth',1.2, 'DisplayName','Null KDE');
    catch
        % fallback: smooth hist
        [f, xi] = ecdf(double(null)); %#ok<ASGLU>
    end
    % vertical line for observed
    yl = ylim(h.ax);
    h.obsLine = plot(h.ax, [obs obs], yl, '-', 'Color', C.curve, 'LineWidth',2.0, 'DisplayName','Observed');
    % annotate p-values if available
    txts = {};
    if isfield(out,'inference') && isfield(out.inference,'pointwise')
        p_pt = out.inference.pointwise.p;
        txts{end+1} = sprintf('Pointwise p = %.3g', p_pt);
    end
    if isfield(out,'inference') && isfield(out.inference,'maxT')
        p_mt = out.inference.maxT.p_corr;
        txts{end+1} = sprintf('maxT p = %.3g', p_mt);
    end
    if isfield(out,'inference') && isfield(out.inference,'tfce')
        p_tf = out.inference.tfce.p_corr;
        txts{end+1} = sprintf('TFCE p = %.3g', p_tf);
    end
    if ~isempty(txts)
        xR = xlim(h.ax);
        yR = ylim(h.ax);
        xText = xR(1) + 0.02*range(xR);
        yText = yR(2) - 0.05*range(yR);
        h.txt = text(h.ax, xText, yText, strjoin(txts,'  |  '), 'FontSize',opt.fontSize, 'Interpreter','none', 'VerticalAlignment','top');
    end
    xlabel(h.ax, tern(strcmpi(pairMetric,'corr'),'ISC (r)','ISC'));
    ylabel(h.ax, 'Density');
    title(h.ax, ttl);
    legend(h.ax, 'Location','best');
else
    % ====================== TIME-RESOLVED VIEW ======================
    % curve
    h.curve = plot(h.ax, t, group, '-', 'Color', C.curve, 'LineWidth', opt.lineWidth, 'DisplayName','Group ISC');
    xlabel(h.ax, 'Time'); ylabel(h.ax, ylab); title(h.ax, ttl);

    % Pointwise (uncorrected band for context)
    if isfield(out,'inference') && isfield(out.inference,'pointwise') && opt.showPointwiseBand
        thr = out.inference.pointwise.thr(:)';         % 1 x T
        % Symmetric band: [0..thr] is not symmetric, so just show upper band
        h.band = fillBand(h.ax, t, thr, min(group, min(thr)), C.band, 0.35);
        uistack(h.band,'bottom');  % behind lines
        plot(h.ax, t, thr, '-', 'Color', C.pointwise, 'LineWidth', 1.0, 'DisplayName', sprintf('Pointwise %.0f%% null', (1-alpha)*100));
    end

    % Now overlays per selected mode(s)
    % Helper to apply minRun to mask:
    applyRun = @(mask) enforce_min_run(mask(:)', opt.minRun);

    modes_to_draw = string(modeList);
    for m = modes_to_draw(:)'
        switch m
            case "pointwise"
                if isfield(out,'inference') && isfield(out.inference,'pointwise')
                    mask = logical(out.inference.pointwise.sigMask);
                    mask = applyRun(mask);
                    if any(mask)
                        h.pt_sig = shadeSpans(h.ax, t, mask, C.pointwise, 0.25, 'Pointwise sig');
                    end
                end
            case "maxT"
                if isfield(out,'inference') && isfield(out.inference,'maxT')
                    critZ = out.inference.maxT.critZ;
                    % If you want to show z threshold on a secondary axis, that complicates format.
                    % Here we just shade significant timepoints by maxT as a distinct overlay.
                    mask = logical(out.inference.maxT.sigMask);
                    mask = applyRun(mask);
                    if any(mask)
                        h.mt_sig = shadeSpans(h.ax, t, mask, C.maxT, 0.20, 'maxT sig');
                    end
                end
            case "cluster"
                if isfield(out,'inference') && isfield(out.inference,'cluster')
                    mask = logical(out.inference.cluster.sigMaskFWER);
                    mask = applyRun(mask);
                    if any(mask)
                        h.cl_sig = shadeSpans(h.ax, t, mask, C.cluster, 0.25, 'Cluster-FWER sig');
                    end
                end
            case "tfce"
                if isfield(out,'inference') && isfield(out.inference,'tfce')
                    mask = logical(out.inference.tfce.sigMask);
                    mask = applyRun(mask);
                    if any(mask)
                        h.tfce_sig = shadeSpans(h.ax, t, mask, C.tfce, 0.20, 'TFCE sig');
                    end
                end
            case "static"
                % nothing—handled above
        end
    end

    % Legend
    legend(h.ax,'Location','best');
end

% Tight layout and save
set(h.ax,'Layer','top');
if strlength(opt.savePath)>0
    [outDir,~,~] = fileparts(char(opt.savePath));
    if ~isempty(outDir) && ~exist(outDir,'dir'), mkdir(outDir); end
    exportgraphics(h.fig, char(opt.savePath), 'Resolution', 300);
end

end % plot_isc_test


% ==================== Local helpers ====================

function txt = tern(cond, a, b)
if cond, txt = a; else, txt = b; end
end

function h = fillBand(ax, t, yTop, yBot, color, alpha)
% Fill area between yTop and yBot
t = t(:)'; yTop = yTop(:)'; yBot = yBot(:)';
yBot = min(yBot, yTop);  % ensure not inverted
X = [t, fliplr(t)];
Y = [yTop, fliplr(yBot)];
h = fill(ax, X, Y, color, 'FaceAlpha', alpha, 'EdgeColor','none', 'DisplayName','Pointwise band');
end

function mask2 = enforce_min_run(mask, minRun)
% Keep only runs with length >= minRun (in samples). minRun=0 => unchanged.
if minRun<=1, mask2 = mask; return; end
runs = get_runs(mask);
mask2 = false(size(mask));
for i = 1:size(runs,1)
    if (runs(i,2)-runs(i,1)+1) >= minRun
        mask2(runs(i,1):runs(i,2)) = true;
    end
end
end

function spans = get_runs(mask)
% Return [start end] rows for contiguous true runs.
mask = logical(mask(:))';
d = diff([false, mask, false]);
starts = find(d==1);
ends   = find(d==-1)-1;
spans = [starts(:), ends(:)];
end

function ph = shadeSpans(ax, t, mask, color, alpha, label)
% Shade each contiguous run in 'mask' as a translucent box spanning full y-range.
spans = get_runs(mask);
yl = ylim(ax);
ph = gobjects(0);
for i=1:size(spans,1)
    s = spans(i,1); e = spans(i,2);
    X = [t(s) t(e) t(e) t(s)];
    Y = [yl(1) yl(1) yl(2) yl(2)];
    isFirst = (i==1);
    ph(end+1) = patch('Parent',ax, 'XData',X, 'YData',Y, ...
        'FaceColor',color, 'FaceAlpha',alpha, 'EdgeColor','none', ...
        'DisplayName', tern(isFirst,label,''));
end
uistack(ph,'bottom');  % keep under lines
end
