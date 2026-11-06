function [ISC_mean, t_sec, ax_time, ax_topo, meta] = plot_isc_timecourse(Y, A, chanlocs, varargin)
% PLOT_ISCtr  Plot CORRCA component topography (left) and time-resolved ISC (right).
%
%   [ISC_mean, t_sec, ax_time, ax_topo, meta] = plot_isc_timecourse(Y, A, chanlocs, ...)
%
% INPUTS
%   Y        : CORRCA time series.
%              - If size(Y) = [T x nComp x nSub], the function extracts the
%                requested component from the second dimension.
%              - If size(Y) = [T x nSub], it is treated as a single
%                component already projected onto CORRCA space.
%   A        : Forward-model activation patterns, size [nChan x nComp].
%   chanlocs : EEGLAB chanlocs structure for topoplot.
%
% OPTIONAL NAME-VALUE PAIRS
%   'Fs'           : Sampling rate in Hz (default: 250).
%   'Comp'         : CORRCA component index (default: 1).
%   'ISCArgs'      : Cell array of name-value pairs forwarded to
%                    movie.compute_isc.
%   'ISC'          : Vector of overall ISC per component (e.g., static ISC
%                    across the whole time range). If provided, the value
%                    for the selected component is shown above the topo.
%
%   Plot appearance:
%   'Color'        : Line color for ISC (default: [0 0.45 0.74]).
%   'LineWidth'    : Line width for ISC curve (default: 1.5).
%   'YLim'         : [ymin ymax] for ISC axis. If empty, computed from data.
%   'Title'        : Global title string for the whole figure (default: '').
%   'ShowZero'     : Logical, plot horizontal zero line (default: true).
%
%   Layout:
%   'TimeAxisPos'  : [x y w h] for ISC axis (default: right panel).
%   'TopoPos'      : [x y w h] for topo axis (default: left panel).
%   'ParentFig'    : Figure handle to plot into (default: new figure).
%
%   Topo / colorbar:
%   'TopoCMap'     : Colormap name or matrix for topo (default: 'turbo').
%   'ShowColorbar' : Logical, show colorbar for topo (default: true).
%   'CBLabel'      : Label for topo colorbar (default: 'a.u.').

% ---------------- Parse inputs ----------------
p = inputParser;
p.FunctionName = 'plot_isc_timecourse';

addRequired(p, 'Y',        @(x) isnumeric(x) && ndims(x) >= 2);
addRequired(p, 'A',        @(x) isnumeric(x));
addRequired(p, 'chanlocs');

addParameter(p, 'Fs',           250,    @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'Comp',         1,      @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'ISCArgs',      {},     @(x) iscell(x));
addParameter(p, 'ISC',          [],     @(x) isempty(x) || (isnumeric(x) && isvector(x)));

addParameter(p, 'Color',        [0 0.45 0.74], @(x) isnumeric(x) && numel(x) == 3);
addParameter(p, 'LineWidth',    1.5,           @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'YLim',         [],            @(x) isempty(x) || (isnumeric(x) && numel(x) == 2));
addParameter(p, 'Title',        '',            @(x) ischar(x) || isstring(x));
addParameter(p, 'ShowZero',     true,          @(x) islogical(x) && isscalar(x));

% Layout: topo left, ISC right (wider figure)
addParameter(p, 'TimeAxisPos',  [0.42 0.16 0.53 0.70], @(x) isnumeric(x) && numel(x) == 4);
addParameter(p, 'TopoPos',      [0.08 0.20 0.25 0.60], @(x) isnumeric(x) && numel(x) == 4);
addParameter(p, 'ParentFig',    [], @(x) isempty(x) || ishghandle(x, 'figure'));

addParameter(p, 'TopoCMap',     'turbo');
addParameter(p, 'ShowColorbar', true,  @(x) islogical(x) && isscalar(x));
addParameter(p, 'CBLabel',      'a.u.', @(x) ischar(x) || isstring(x));

parse(p, Y, A, chanlocs, varargin{:});
opt = p.Results;

Fs       = opt.Fs;
compIdx  = opt.Comp;
iscArgs  = opt.ISCArgs;
ISC_vec  = opt.ISC;

% font sizes
fs_title   = 13;   % global title
fs_label   = 11;   % axis labels
fs_ticks   = 10;   % tick labels
fs_cb_lbl  = 12;   % colorbar label
fs_cb_tick = 10;   % colorbar ticks
fs_topotxt = 11;   % "Forward model" text

% ---------------- Prepare figure & axes ----------------
if isempty(opt.ParentFig) || ~ishghandle(opt.ParentFig, 'figure')
    fig = figure('Color','w', ...
                 'Units','centimeters', ...
                 'Position',[2 2 26 8]);  % wider, more balanced
else
    fig = opt.ParentFig;
    figure(fig);
    set(fig, 'Color','w');
end

% Topo on the left
ax_topo = axes('Position', opt.TopoPos);
set(ax_topo, 'Visible', 'off', 'Color','w');

% Time-resolved ISC on the right
ax_time = axes('Position', opt.TimeAxisPos);
hold(ax_time, 'on');
set(ax_time, 'Color','w');

% ---------------- Extract CORRCA component ----------------
Ydims = size(Y);
if ndims(Y) == 3
    if compIdx > Ydims(2)
        error('Comp index %d exceeds number of components (%d) in Y.', compIdx, Ydims(2));
    end
    Ycomp = squeeze(Y(:, compIdx, :));  % [T x nSub]
elseif ismatrix(Y)
    Ycomp = Y;                          % [T x nSub]
else
    error('Y must be 2D or 3D (T x nComp x nSub).');
end

[T, nSub] = size(Ycomp); %#ok<NASGU>

% ---------------- Run ISC per subject ----------------
if ~iscell(iscArgs)
    error('ISCArgs must be a cell array of name-value pairs.');
end

[ISCtr, meta] = movie.compute_isc(Ycomp, iscArgs{:});

ISC_size = size(ISCtr);
if numel(ISC_size) > 3
    error('Unexpected ISCtr dimensions. Expected [nSub x nWin] or [nSub x nWin x ...].');
end
ISCtr = reshape(ISCtr, ISC_size(1), []);  % nSub x nWin
nWin  = size(ISCtr, 2);

ISC_mean = mean(ISCtr, 1);

% Overall ISC for this component (if provided)
compISC = NaN;
if ~isempty(ISC_vec) && numel(ISC_vec) >= compIdx
    compISC = ISC_vec(compIdx);
end

% Grand-average time-resolved ISC (mean over time)
ISC_mean_over_time = mean(ISC_mean, 'omitnan');

% ---------------- Build time axis ----------------
if nWin > 1
    winLength = [];
    overlap   = [];
    for k = 1:2:numel(iscArgs)
        if ischar(iscArgs{k}) || isstring(iscArgs{k})
            switch lower(iscArgs{k})
                case 'winlength'
                    winLength = iscArgs{k+1};
                case 'overlap'
                    overlap = iscArgs{k+1};
            end
        end
    end
    if isempty(winLength)
        warning('winLength not found in ISCArgs; approximating from T/nWin.');
        winLength = T / nWin;
    end
    if isempty(overlap)
        if nWin > 1
            stepSamples = (T - winLength) / (nWin - 1);
        else
            stepSamples = winLength;
        end
    else
        stepSamples = winLength * (1 - overlap);
    end

    centersSamples = winLength/2 + (0:nWin-1) * stepSamples;
    t_sec = centersSamples / Fs;
else
    t_sec = 0;
end

% ---------------- Plot time-resolved ISC ----------------
plot(ax_time, t_sec, ISC_mean, ...
    'Color', opt.Color, ...
    'LineWidth', opt.LineWidth);

if opt.ShowZero
    xl = [t_sec(1) t_sec(end)];
    plot(ax_time, xl, [0 0], ':', 'Color', [0.6 0.6 0.6], 'LineWidth', 0.5);
end

xlim(ax_time, [t_sec(1) t_sec(end)]);
xlabel(ax_time, 'Time (s)', 'FontSize', fs_label);
ylabel(ax_time, 'ISC (r)',  'FontSize', fs_label);

set(ax_time, ...
    'Box','off', ...
    'TickDir','out', ...
    'FontName','Arial', ...
    'FontSize', fs_ticks, ...   % tick labels
    'Layer','top');

% ----- Y-limits: 1.05× expansion, then add ~10% headroom at top -----
if isempty(opt.YLim)
    ymin = min(ISC_mean);
    ymax = max(ISC_mean);

    if ymin == ymax
        if ymin == 0
            ymin = -0.001;
            ymax =  0.001;
        else
            delta = 0.05 * abs(ymin);
            ymin  = ymin - delta;
            ymax  = ymax + delta;
        end
    else
        if ymin < 0
            ymin = ymin * 1.05;
        else
            ymin = ymin * 0.95;
        end
        if ymax > 0
            ymax = ymax * 1.05;
        else
            ymax = ymax * 0.95;
        end
    end

    ylim(ax_time, [ymin ymax]);
else
    ylim(ax_time, opt.YLim);
end

% Add extra headroom at the top to make room for text
yl = ylim(ax_time);
rangeY = yl(2) - yl(1);
if rangeY == 0
    rangeY = max(abs(yl));
end
yl(2) = yl(2) + 0.10 * rangeY;   % +10% headroom
ylim(ax_time, yl);

ax_time.YRuler.Exponent = 0;
ytickformat(ax_time, '%.4f');

% Text: grand-average time-resolved ISC in top-right corner of line plot
if ~isnan(ISC_mean_over_time)
    txt_str = sprintf('Mean ISC_{TR} = %.3f', ISC_mean_over_time);
    text(ax_time, 0.98, 0.92, txt_str, ...
        'Units', 'normalized', ...
        'HorizontalAlignment', 'right', ...
        'VerticalAlignment', 'bottom', ...
        'FontSize', fs_ticks, ...
        'FontName', 'Arial');
end

% ---------------- Global title (centered over whole figure) ----------------
if ~isempty(opt.Title)
    try
        sgtitle(opt.Title, 'FontSize', fs_title, 'FontWeight','normal');
    catch
        % Older MATLAB without sgtitle
        annotation(fig, 'textbox', [0 0.94 1 0.06], ...
            'Units', 'normalized', ...
            'String', opt.Title, ...
            'EdgeColor', 'none', ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'top', ...
            'FontSize', fs_title, ...
            'FontWeight', 'normal');
    end
end

% ---------------- Topo (left panel) ----------------
axes(ax_topo); %#ok<LAXES>
pattern = A(:, compIdx);
topoplot(pattern, chanlocs, ...
    'electrodes','off', ...
    'numcontour', 0);


axis(ax_topo, 'off');
set(ax_topo, 'Color','w');

cmax = max(abs(pattern));
if cmax == 0
    cmax = 1;
end
caxis(ax_topo, [-cmax cmax]);

if isnumeric(opt.TopoCMap)
    colormap(ax_topo, opt.TopoCMap);
elseif ischar(opt.TopoCMap) || isstring(opt.TopoCMap)
    colormap(ax_topo, char(opt.TopoCMap));
else
    error('TopoCMap must be either a colormap name (char/string) or an Nx3 numeric matrix.');
end

% Text: original overall ISC for this component above the topo
if ~isnan(compISC)
    txt_ISC = sprintf('ISC = %.3f', compISC);
    text(ax_topo, 0.5, 1.02, txt_ISC, ...
        'Units', 'normalized', ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'bottom', ...
        'FontSize', fs_ticks, ...
        'FontName', 'Arial');
end

if opt.ShowColorbar
    cb = colorbar(ax_topo, 'Location', 'eastoutside');

    % Tick font
    cb.FontSize = fs_cb_tick;

    % Put label on top of the vertical colorbar
    title(cb, opt.CBLabel, 'FontSize', fs_cb_lbl, 'FontName', 'Arial');
end

% ---------------- "Forward model" text under topo ----------------
text(ax_topo, 0.5, -0.05, 'Forward model', ...
        'Units', 'normalized', ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'top', ...
        'FontSize', fs_topotxt, ...
        'FontName', 'Arial');


axes(ax_time);  % back to time axis

end
