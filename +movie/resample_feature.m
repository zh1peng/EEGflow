function y_tgt = resample_feature(t_src, y_src, t_tgt, mode, varargin)
%RESAMPLE_FEATURE  Resample a single feature onto a target time grid.
%
% y_tgt = resample_feature(t_src, y_src, t_tgt, mode, 'Name', Value, ...)
%
% Inputs
%   t_src : [T x 1] source timestamps in seconds (irregular OK)
%   y_src : [T x 1] source values (numeric/logical)
%   t_tgt : [K x 1] target time grid in seconds (uniform EEG grid, etc.)
%   mode  : 'hold'    -> step-wise (zero-order hold / previous value)
%           'interp'  -> continuous interpolation ('pchip' or 'linear')
%           'binmean' -> windowed mean in bins around each t_tgt
%
% Name-Value options
%   'InterpMethod' : interpolation for 'interp' mode:
%                    'pchip' (default) | 'linear'
%   'OffsetSec'    : shift source times by this many seconds (default 0)
%   'Fill'         : handle NaNs after resampling:
%                    'ffill' (default) -> forward-fill internal NaNs
%                    'bfill'           -> back-fill internal NaNs
%                    'zero'            -> set NaNs to 0
%                    'none'            -> leave NaNs
%   'BinWidthSec'  : bin width (seconds) for 'binmean' mode.
%                    Default: median diff(t_tgt).
%
% Visualization (optional)
%   'MakePlot'     : true/false to show a sanity plot (default: false)
%   'Ax'           : axis handle to draw into (default: [])
%   'PlotWindow'   : [t0 t1] seconds to zoom plot (default: [])
%   'SourceStyle'  : struct for the source scatter (e.g., MarkerSize)
%   'TargetStyle'  : struct for the target line   (e.g., LineWidth)
%   'Title'        : custom title string (default auto)
%
% Output
%   y_tgt : [K x 1] resampled values aligned to t_tgt
%
% Notes
% - Recommended usage:
%     * Impulse-like/binary/categorical → mode='hold'
%     * Continuous, especially downsampling → mode='binmean'
%     * Mild upsampling of smooth features → mode='interp'
% - 'binmean' does proper time-window averaging, which is safer when
%   going from higher to lower temporal resolution (e.g. 10 Hz → 1 Hz).
% -------------------------------------------------------------------------

% -------------------- parse options --------------------
p = inputParser;
p.addParameter('InterpMethod','pchip', @(s)ischar(s)&&ismember(lower(s),{'pchip','linear'}));
p.addParameter('OffsetSec',0, @(x)isnumeric(x)&&isscalar(x));
p.addParameter('Fill','ffill', @(s)ischar(s)&&ismember(lower(s),{'ffill','bfill','zero','none'}));
p.addParameter('BinWidthSec',[], @(x) isempty(x) || (isnumeric(x)&&isscalar(x)&&x>0));

% viz
p.addParameter('MakePlot',false, @(x)islogical(x)&&isscalar(x));
p.addParameter('Ax',[], @(h) isempty(h) || isgraphics(h,'axes'));
p.addParameter('PlotWindow',[], @(x) isempty(x) || (isnumeric(x)&&numel(x)==2));
p.addParameter('SourceStyle',struct(), @isstruct);
p.addParameter('TargetStyle',struct(), @isstruct);
p.addParameter('Title','', @(s)ischar(s) || isstring(s));
p.parse(varargin{:});
opt = p.Results;

% -------------------- normalize/validate --------------------
t_src = t_src(:) + opt.OffsetSec;
y_src = y_src(:);
t_tgt = t_tgt(:);

% Drop NaN/Inf times
ok = isfinite(t_src);
t_src = t_src(ok);
y_src = y_src(ok);

% If nothing usable, return zeros (and optional plot)
if isempty(t_src) || isempty(y_src) || all(~isfinite(y_src))
    y_tgt = zeros(size(t_tgt));
    if opt.MakePlot, local_plot(t_src, y_src, t_tgt, y_tgt, opt, mode); end
    return;
end

% Sort ascending
[ts, ord] = sort(t_src, 'ascend');
ys = y_src(ord);

% Handle duplicates (keep first)
[tu, ia] = unique(ts, 'stable');
t_src = tu;
y_src = ys(ia);

% Precompute target step for binning
if numel(t_tgt) > 1
    dt_tgt = median(diff(t_tgt), 'omitnan');
else
    dt_tgt = 1; % arbitrary
end
if isempty(opt.BinWidthSec)
    binWidth = dt_tgt;
else
    binWidth = opt.BinWidthSec;
end

% -------------------- resample modes --------------------
mode_l = lower(mode);

switch mode_l
    case 'hold'
        % Step/hold (previous) WITHOUT extrapolation
        y = interp1(t_src, y_src, t_tgt, 'previous');
        % Internal gaps only: forward-fill (no look-ahead)
        y = fillmissing(y, 'previous');

        % Edge policy: zero outside source support
        edge_left_zero  = true;
        edge_right_zero = true;

    case 'interp'
        % Continuous interpolation WITHOUT extrapolation
        y = interp1(t_src, y_src, t_tgt, opt.InterpMethod);

        % Edge policy: zero outside source support (for consistency)
        edge_left_zero  = true;
        edge_right_zero = true;

    case 'binmean'
        % Windowed mean in bins around each t_tgt.
        %
        % Bin edges are centered on t_tgt with width = binWidth:
        %   [t_tgt(1)-binWidth/2, t_tgt(1)+binWidth/2, t_tgt(2)+binWidth/2, ...]
        %
        % This is appropriate for proper downsampling of continuous features.
        edges = [t_tgt - binWidth/2; t_tgt(end) + binWidth/2];
        [~,~,bin] = histcounts(t_src, edges);

        y = nan(size(t_tgt));
        for k = 1:numel(t_tgt)
            idx = (bin == k);
            if any(idx)
                y(k) = mean(y_src(idx), 'omitnan');
            else
                y(k) = NaN;
            end
        end

        % For binmean we *don't* force zeros outside source range explicitly;
        % bins without samples will be handled by the Fill policy below.
        edge_left_zero  = false;
        edge_right_zero = false;

    otherwise
        error('Unknown mode "%s". Use "hold", "interp", or "binmean".', mode);
end

% -------------------- edges and post-fill --------------------
if edge_left_zero || edge_right_zero
    left_edge  = t_tgt < t_src(1);
    right_edge = t_tgt > t_src(end);

    if edge_left_zero
        y(left_edge) = 0;
    end
    if edge_right_zero
        y(right_edge) = 0;
    end
end

% Now address any remaining internal NaNs based on requested Fill policy
switch lower(opt.Fill)
    case 'ffill'   % forward fill internal NaNs only
        y = fillmissing(y, 'previous');
    case 'bfill'   % back fill internal NaNs only
        y = fillmissing(y, 'next');
    case 'zero'
        y(~isfinite(y)) = 0;
    case 'none'
        % leave NaNs as-is
end

% Final cleanup (avoid Infs)
y(~isfinite(y)) = 0;

y_tgt = y;

% -------------------- optional visualization --------------------
if opt.MakePlot
    local_plot(t_src, y_src, t_tgt, y_tgt, opt, mode);
end
end

% ==================== local helpers ====================
function local_plot(t_src, y_src, t_tgt, y_tgt, opt, mode)
    % Axis
    if isempty(opt.Ax)
        fig = figure('Color','w','Name','Resample One Feature'); %#ok<NASGU>
        ax = axes; hold(ax,'on');
    else
        ax = opt.Ax; hold(ax,'on');
    end

    % Styles (defaults + user overrides)
    srcStyle = struct('Marker','o','MarkerSize',5,'LineStyle','none','Color','k','DisplayName','source');
    tgtStyle = struct('LineWidth',1.4,'Color',[0 0.4470 0.7410],'DisplayName','resampled');
    srcStyle = local_merge_struct(srcStyle, opt.SourceStyle);
    tgtStyle = local_merge_struct(tgtStyle, opt.TargetStyle);

    % Plot
    if ~isempty(t_src) && ~isempty(y_src)
        plot(ax, t_src, y_src, srcStyle);
    end
    plot(ax, t_tgt, y_tgt, tgtStyle);

    % Window
    if ~isempty(opt.PlotWindow)
        xlim(ax, [max(opt.PlotWindow(1), min(t_tgt)) , min(opt.PlotWindow(2), max(t_tgt))]);
    else
        xlim(ax, [min(t_tgt) max(t_tgt)]);
    end

    grid(ax,'on');
    xlabel(ax,'Time (s)'); ylabel(ax,'Value');

    ttl = strtrim(string(opt.Title));
    if ttl == ""
        ttl = sprintf('Resample (%s)', lower(mode));
    end
    title(ax, ttl, 'Interpreter','none');

    legend(ax,'Location','best'); legend(ax,'boxoff');
end

function S = local_merge_struct(S, U)
    if isempty(U), return; end
    f = fieldnames(U);
    for i = 1:numel(f)
        S.(f{i}) = U.(f{i});
    end
end
