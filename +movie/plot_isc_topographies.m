function fig = plot_isc_topographies(A_cell, chanlocs, varargin)
% PLOT_ISC_TOPOGRAPHIES
%   Topography grid: rows = bands, columns = components.
%
%   fig = plot_isc_topographies(A_cell, chanlocs, 'Name', value, ...)
%
% INPUT
%   A_cell  : cell array (nBands x 1), each [nChan x nComp]
%   chanlocs: EEGLAB chanlocs struct
%
% NAME–VALUE
%   'CompList'   : vector of component indices (default: 1:3 or up to available)
%   'BandLabels' : cellstr row labels (e.g., {'\delta','\theta',...})
%   'TopoCMap'   : colormap name or matrix (default: 'turbo')
%   'CBLabel'    : colorbar label (default: 'a.u.')
%   'Title'      : figure title (default: '')
%
% NOTE: Uses a single global color scale across ALL bands & components.

if ~iscell(A_cell) || isempty(A_cell)
    error('A_cell must be a non-empty cell array.');
end
nBands = numel(A_cell);

p = inputParser;
p.addParameter('CompList',   [], @(x)isnumeric(x)&&isvector(x));
p.addParameter('BandLabels', [], @(x)iscellstr(x)||isstring(x)||isempty(x));
p.addParameter('TopoCMap', 'turbo', @(x)ischar(x)||isstring(x)||isnumeric(x));
p.addParameter('CBLabel',  'a.u.', @(x)ischar(x)||isstring(x));
p.addParameter('Title',    '', @(x)ischar(x)||isstring(x));
p.addParameter('ShowColorbar', true, @(x)isa(x,'logical'));
p.addParameter('ShowYBandLabels', false, @(x)isa(x,'logical'));
p.addParameter('ShowTopoLabels', false, @(x)isa(x,'logical'));
p.parse(varargin{:});
opt = p.Results;

A1 = A_cell{1};
[nChan, nCompAvail] = size(A1); %#ok<ASGLU>

if isempty(opt.CompList)
    compList = 1:min(3,nCompAvail);
else
    compList = opt.CompList(:)';
    if any(compList<1) || any(compList>nCompAvail)
        error('CompList indices exceed available components (%d).', nCompAvail);
    end
end
nComp = numel(compList);

% default band labels
if isempty(opt.BandLabels)
    defaultBands = {'Delta','Theta','Alpha','Beta','Gamma'};
    if nBands <= numel(defaultBands)
        bandLabels = defaultBands(1:nBands);
    else
        bandLabels = arrayfun(@(k)sprintf('Band %d',k),1:nBands,'UniformOutput',false);
    end
else
    bandLabels = cellstr(opt.BandLabels);
    if numel(bandLabels) ~= nBands
        error('BandLabels must have length equal to numel(A_cell).');
    end
end

% global color scale
allVals = [];
for b = 1:nBands
    Ab = A_cell{b};
    if size(Ab,1) ~= nChan || size(Ab,2) < max(compList)
        error('A_cell{%d} has incompatible size.', b);
    end
    allVals = [allVals; Ab(:,compList)]; %#ok<AGROW>
end
cmax = max(abs(allVals(:)));
if cmax == 0, cmax = 1; end
cLim = [-cmax cmax];

% figure
fig = figure('Color','w', ...
             'Units','centimeters', ...
             'Position',[2 2 4*nComp 3*nBands]);

t = tiledlayout(nBands, nComp, 'TileSpacing','none', 'Padding','none');

% store axes handles in a grid
axGrid = gobjects(nBands, nComp);

for b = 1:nBands
    for ic = 1:nComp
        compIdx = compList(ic);

        axGrid(b,ic) = nexttile(t);  % << store axes handle
        pattern = A_cell{b}(:,compIdx);

        topoplot(pattern, chanlocs, ...
            'electrodes','off', ...
            'numcontour', 0);
        caxis(cLim);
        axis off;

        if isnumeric(opt.TopoCMap)
            colormap(axGrid(b,ic), opt.TopoCMap);
        else
            colormap(axGrid(b,ic), char(opt.TopoCMap));
        end

        if b == 1 && opt.ShowTopoLabels
            title(sprintf('Comp %d', compIdx), 'FontSize', 10);
        end
        if ic == 1 && opt.ShowYBandLabels
            ylabel(bandLabels{b}, 'FontSize', 10, 'FontWeight','normal');
        end
    end
end

% ----- left-margin band labels (one per row) -----
if opt.ShowYBandLabels
    for b = 1:nBands
        text(axGrid(b,1), -0.15, 0.5, bandLabels{b}, ...
            'Units', 'normalized', ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment',   'middle', ...
        'FontSize', 11, ...
        'FontWeight', 'bold');
    end
end


% ----- global colorbar, centered on right margin -----
% use the middle row, last column as the peer for the colorbar
if opt.ShowColorbar
    midRow   = ceil(nBands/2);
    ax_for_cb = axGrid(midRow, end);
    axes(ax_for_cb);  % make it current for older MATLAB

    cb = colorbar(ax_for_cb, 'Location', 'eastoutside');
    cb.Label.String   = char(opt.CBLabel);
    cb.Label.FontSize = 11;

    % center vertically along the right edge
    pos = cb.Position;         % [x y w h] in normalized figure units
    pos(1) = 0.92;             % near right margin (tweak if needed)
    pos(2) = 0.5 - pos(4)/2;   % vertical center
    cb.Position = pos;
end
% global title (if supported)
if ~isempty(opt.Title)
    try
        title(t, char(opt.Title), 'FontSize', 12, 'FontWeight','normal');
    catch
        % fallback: basic annotation at top
        annotation(fig, 'textbox', [0 0.96 1 0.04], ...
            'String', char(opt.Title), ...
            'HorizontalAlignment','center', ...
            'VerticalAlignment','top', ...
            'EdgeColor','none', ...
            'FontSize', 12, ...
            'FontWeight','normal');
    end
end
end
