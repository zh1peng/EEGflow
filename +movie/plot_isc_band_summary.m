function [stats, ax] = plot_isc_band_summary(Y_cell, varargin)
% PLOT_ISC_BAND_SUMMARY  Summarize ISC across frequency bands & components.
%
%   [stats, ax] = plot_isc_band_summary(Y_cell, 'Name', value, ...)
%
% INPUT
%   Y_cell : cell array (nBands x 1), each element is CORRCA time series
%            for a single band:
%            - [T x nComp x nSub]  OR
%            - [T x nSub]          (single component)
%
%   This function:
%     1) Computes per-subject ISC for each band & component using
%        movie.compute_isc.
%     2) Averages over time (if time-resolved) to get one ISC per subject.
%     3) Computes group mean & std across subjects.
%     4) Plots either:
%        - 'bar'   : grouped bar per band (x), components as bars
%        - 'scree' : line+marker per component across bands
%
% REQUIRED: movie.compute_isc.m must be on path.
%
% NAME–VALUE OPTIONS
%   'ISCArgs'      : cell array of name–value args for movie.compute_isc.
%                    Default: {} (use your function's defaults).
%
%   'Mode'         : 'bar' | 'scree'     ['bar']
%                    If numel(Y_cell)==1, forced to 'bar'.
%
%   'CompList'     : vector of component indices to include (e.g., [1 2 3]).
%                    Default: 1:3 or up to available components.
%
%   'BandLabels'   : cellstr of band names for x-axis.
%                    Default: {'δ','θ','α','β','γ'} truncated to nBands.
%
%   'CompLabels'   : cellstr for legend in scree mode / annotation.
%
%   'CompColors'   : [nComp x 3] RGB for components.
%                    Default: mildly saturated, harmonized:
%                      C1: [0.90 0.40 0.40]
%                      C2: [0.45 0.70 0.95]
%                      C3: [0.70 0.60 0.90]
%
%   'YLim'         : [ymin ymax] for ISC axis. Default: auto, with padding.
%
%   'YLabel'       : string for y-axis. Default: 'Mean ISC (r)'.
%   'Title'        : figure title. Default: ''.
%
%   'BarWidth'     : bar width for 'bar' mode.   [0.7]
%   'LineWidth'    : line width for lines/bars.  [1.5]
%   'MarkerSize'   : marker size for scree.      [50]
%
%   'ShowErrorBar' : logical, show std error bars [true]
%   'ShowAxesBox'  : logical, axes visible        [true]
%   'ShowXTickLabel': logical, show x tick labels [true]
%   'ShowYTickLabel': logical, show y tick labels [true]
%
% OUTPUT
%   stats : struct with fields
%           .meanISC   [nBands x nComp]
%           .stdISC    [nBands x nComp]
%           .bands     (cellstr)
%           .compList  (vector)
%   ax    : axes handle for the summary plot.

% ---------------- parse inputs ----------------
if ~iscell(Y_cell) || isempty(Y_cell)
    error('Y_cell must be a non-empty cell array.');
end
nBands = numel(Y_cell);

p = inputParser;
p.FunctionName = 'plot_isc_band_summary';

p.addParameter('ISCArgs',      {}, @(x)iscell(x));
p.addParameter('Mode',       'bar', @(x)ischar(x)||isstring(x));
p.addParameter('CompList',     [], @(x)isnumeric(x)&&isvector(x));
p.addParameter('BandLabels',   [], @(x)iscellstr(x)||isstring(x)||isempty(x));
p.addParameter('CompLabels',   [], @(x)iscellstr(x)||isstring(x)||isempty(x));
p.addParameter('CompColors',   [], @(x)isnumeric(x)||isempty(x));
p.addParameter('YLim',         [], @(x)isnumeric(x)&&numel(x)==2||isempty(x));
p.addParameter('YLabel', 'Mean ISC (r)', @(x)ischar(x)||isstring(x));
p.addParameter('Title',        '', @(x)ischar(x)||isstring(x));

p.addParameter('BarWidth',    0.7, @(x)isnumeric(x)&&isscalar(x));
p.addParameter('LineWidth',   1.5, @(x)isnumeric(x)&&isscalar(x));
p.addParameter('MarkerSize',   50, @(x)isnumeric(x)&&isscalar(x));

p.addParameter('ShowErrorBar',  true, @(x)islogical(x)||ismember(x,[0 1]));
p.addParameter('ShowAxesBox',   true, @(x)islogical(x)||ismember(x,[0 1]));
p.addParameter('ShowXTickLabel',true, @(x)islogical(x)||ismember(x,[0 1]));
p.addParameter('ShowYTickLabel',true, @(x)islogical(x)||ismember(x,[0 1]));

p.parse(varargin{:});
opt = p.Results;

mode = lower(char(opt.Mode));
if nBands == 1
    mode = 'bar';   % force bar mode for single-band
end

% default band labels
if isempty(opt.BandLabels)
    defaultBands = {'\delta','\theta','\alpha','\beta','\gamma'};
    if nBands <= numel(defaultBands)
        bandLabels = defaultBands(1:nBands);
    else
        bandLabels = arrayfun(@(k)sprintf('Band %d',k),1:nBands,'UniformOutput',false);
    end
else
    bandLabels = cellstr(opt.BandLabels);
    if numel(bandLabels) ~= nBands
        error('BandLabels must have length equal to numel(Y_cell) (%d).', nBands);
    end
end

% determine number of components available from first band
Y1 = Y_cell{1};
if ndims(Y1) == 3
    nCompAvail = size(Y1,2);
elseif ismatrix(Y1)
    nCompAvail = 1;
else
    error('Each Y in Y_cell must be 2D or 3D (T x nComp x nSub) or (T x nSub).');
end

% component list
if isempty(opt.CompList)
    compList = 1:min(3,nCompAvail);
else
    compList = opt.CompList(:)';
    if any(compList<1) || any(compList>nCompAvail)
        error('CompList indices exceed available components (%d).', nCompAvail);
    end
end
nComp = numel(compList);

% default component labels
if isempty(opt.CompLabels)
    compLabels = arrayfun(@(c)sprintf('Comp %d',c), compList,'UniformOutput',false);
else
    compLabels = cellstr(opt.CompLabels);
    if numel(compLabels) ~= nComp
        error('CompLabels must have length equal to numel(CompList).');
    end
end

% default component colors (harmonized mild colors)
if isempty(opt.CompColors)
    base = [
        0.90 0.40 0.40;   % C1: warm red
        0.45 0.70 0.95;   % C2: bluish
        0.70 0.60 0.90;   % C3: purple
        0.98 0.90 0.45;   % C4: yellow-ish if needed
    ];
    if nComp <= size(base,1)
        compColors = base(1:nComp,:);
    else
        compColors = lines(nComp);
    end
else
    compColors = opt.CompColors;
    if size(compColors,1) ~= nComp || size(compColors,2) ~= 3
        error('CompColors must be [nComp x 3].');
    end
end

iscArgs = opt.ISCArgs;

% ---------------- compute ISC mean/std ----------------
meanISC = nan(nBands, nComp);
stdISC  = nan(nBands, nComp);

for b = 1:nBands
    Yb = Y_cell{b};

    for ic = 1:nComp
        cidx = compList(ic);

        if ndims(Yb) == 3
            if cidx > size(Yb,2)
                error('Comp %d exceeds components in band %d.', cidx, b);
            end
            Ycomp = squeeze(Yb(:, cidx, :));  % [T x nSub]
        else
            if cidx ~= 1
                error('Y for band %d has only one component.', b);
            end
            Ycomp = Yb;                        % [T x nSub]
        end

        % movie.compute_isc: outputs per-subject ISC, possibly time-resolved
        [ISCtr, ~] = movie.compute_isc(Ycomp, iscArgs{:});
        % reshape to [nSub x nWin] and average across time windows
        sz = size(ISCtr);
        ISCmat = reshape(ISCtr, sz(1), []);        % nSub x nWin
        ISC_sub = mean(ISCmat, 2, 'omitnan');      % nSub x 1

        meanISC(b,ic) = mean(ISC_sub, 'omitnan');
        stdISC(b,ic)  = std(ISC_sub,  0, 'omitnan');
    end
end

stats.meanISC  = meanISC;
stats.stdISC   = stdISC;
stats.bands    = bandLabels;
stats.compList = compList;

% ---------------- plotting ----------------
fig = figure('Color','w', ...
             'Units','centimeters', ...
             'Position',[3 3 10 7]);  % tall-ish

ax = axes('Parent',fig);
hold(ax,'on');

x = 1:nBands;

switch mode
    case 'bar'
        % grouped bar chart: bands on x, components grouped
        b = bar(ax, x, meanISC, opt.BarWidth, 'grouped');
        for ic = 1:nComp
            set(b(ic), 'FaceColor', compColors(ic,:), ...
                       'EdgeColor', 'none');
        end

        if opt.ShowErrorBar
            % compute bar centers for error bars
            xb = nan(size(meanISC));
            for ic = 1:nComp
                xb(:,ic) = b(ic).XEndPoints;
            end
            er = errorbar(ax, xb(:), meanISC(:), stdISC(:), stdISC(:), ...
                'k', 'LineStyle','none', 'LineWidth', 0.8);
            er.CapSize = 4;
        end

       case 'scree'
        % lines across bands, one line per component
        hLines = gobjects(nComp,1);   % store line handles for legend

        for ic = 1:nComp
            hLines(ic) = plot(ax, x, meanISC(:,ic), '-o', ...
                'Color', compColors(ic,:), ...
                'LineWidth', opt.LineWidth, ...
                'MarkerFaceColor', compColors(ic,:), ...
                'MarkerEdgeColor', compColors(ic,:), ...
                'MarkerSize', sqrt(opt.MarkerSize));

            if opt.ShowErrorBar
                hErr = errorbar(ax, x, meanISC(:,ic), stdISC(:,ic), stdISC(:,ic), ...
                    'Color', compColors(ic,:), ...
                    'LineStyle','none', ...
                    'LineWidth', 0.8, ...
                    'CapSize', 4);
                % keep errorbars out of legend
                set(hErr, 'HandleVisibility','off');
            end
        end

    otherwise
        error('Unknown Mode "%s". Use "bar" or "scree".', mode);
end

% x-axis labels
ax.XTick = x;
ax.XTickLabel = bandLabels;
if ~opt.ShowXTickLabel
    ax.XTickLabel = [];
end

% give some padding on x so delta (band 1) is not glued to the y-axis
xlim(ax, [0.5, nBands + 0.5]);

% y-limits
if isempty(opt.YLim)
    ymin = min(meanISC(:) - stdISC(:));
    ymax = max(meanISC(:) + stdISC(:));
    if isempty(ymin) || isempty(ymax) || isnan(ymin) || isnan(ymax)
        ymin = 0; ymax = 1;
    end
    if ymin == ymax
        if ymin == 0
            ymin = -0.001;
            ymax =  0.001;
        else
            delta = 0.1*abs(ymin);
            ymin  = ymin - delta;
            ymax  = ymax + delta;
        end
    else
        span = ymax - ymin;
        ymin = ymin - 0.1*span;
        ymax = ymax + 0.1*span;
    end
    ylim(ax,[ymin ymax]);
else
    ylim(ax,opt.YLim);
end

if opt.ShowYTickLabel
    ylabel(ax, opt.YLabel, 'FontSize', 12);
else
    ax.YTickLabel = [];
    ax.YColor     = 'none';
end

if opt.ShowAxesBox
    box(ax,'off');
else
    axis(ax,'off');
end

set(ax, 'TickDir','out', ...
        'FontName','Arial', ...
        'FontSize',12);

if ~isempty(opt.Title)
    title(ax, opt.Title, 'FontSize', 12, 'FontWeight','normal');
end

if strcmp(mode,'scree')
    % use only the line handles we stored
    legend(ax, hLines, compLabels, ...
        'Location','northwest', ...
        'Box','off');
end

hold(ax,'off');
end
