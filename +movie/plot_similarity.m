function [ax,orderUsed] = plot_similarity(S, varargin)
% PLOT_SIMILARITY  Clean plot for subject-by-subject similarity matrices.
%
%   [ax, orderUsed] = movie.plot_similarity(S, 'Name',Value,...)
%
% NAME-VALUE
%   'mode'           : 'full' (default) | 'upper' | 'lower'
%   'includeDiag'    : true for 'full'; false by default for 'upper'/'lower'
%   'order'          : [] (use given permutation; overrides 'reorder')
%   'reorder'        : false (default) | true
%   'reorderMethod'  : 'hier' (default) | 'spectral' | ...
%   'labels'         : {} cellstr for subjects
%   'clim'           : [] or [cmin cmax] (manual color limits)
%   'colorbar'       : true (default) | false
%   'title'          : ''
%   --- Colormap options ---
%   'cmap'           : 'parula' (default) | name | Nx3 colormap
%   'nColors'        : 256
%   'center'         : 0 (value that maps to midColor; set [] to disable)
%   'symmetric'      : [] -> auto; true|false (only used if 'center' is set and 'clim' not given)
%   'lowColor'       : [135 206 235]/255   (skyblue)
%   'midColor'       : [1 1 1]             (white)
%   'highColor'      : [178 34 34]/255     (firebrick)
%   'discreteLevels' : [] (e.g., 9 for 9-step colormap)
%   'cbarTicks'      : [] (custom ticks)
%
% NOTE: Sorting is for visualization only (keep analysis unsorted).

% EXAMPLES
% movie.plot_similarity(ISCpair, ...
%     'mode','full', ...
%     'clim',[-0.2 0.4], 'center',0, ...
%     'hideDiag', true,...
%     'reorder',true, 'title','ISC');

ip = inputParser;
ip.addParameter('mode','full');
ip.addParameter('includeDiag',[]);          % default set below by mode
ip.addParameter('order',[]);
ip.addParameter('reorder',false,@islogical);
ip.addParameter('reorderMethod','hier');
ip.addParameter('labels',{});
ip.addParameter('clim',[]);
ip.addParameter('colorbar',true,@islogical);
ip.addParameter('title','');

% colormap controls
ip.addParameter('cmap','parula');
ip.addParameter('nColors',256,@isscalar);
ip.addParameter('center',0);                % default 0 -> midColor at 0
ip.addParameter('symmetric',[]);            % auto unless explicitly set
ip.addParameter('lowColor',[135 206 235]/255);
ip.addParameter('midColor',[1 1 1]);
ip.addParameter('highColor',[178 34 34]/255);
ip.addParameter('diagColor',[]);
ip.addParameter('hideDiag',false,@islogical);     
ip.addParameter('discreteLevels',[],@(x) isempty(x) || (isscalar(x) && x>=2));
ip.addParameter('cbarTicks',[]);

ip.parse(varargin{:});
opt = ip.Results;

% includeDiag default by mode
if isempty(opt.includeDiag)
    if strcmpi(opt.mode,'full'), opt.includeDiag = true; else, opt.includeDiag = false; end
end

N = size(S,1);
if isempty(opt.order)
    if opt.reorder
        orderUsed = movie.reorder_similarity(S, 'method',opt.reorderMethod);
    else
        orderUsed = 1:N;
    end
else
    orderUsed = opt.order(:).';
    assert(numel(orderUsed)==N && all(sort(orderUsed)==1:N),'Bad order');
end

S2 = S(orderUsed, orderUsed);

% Mask by mode (without relying on zeros)
switch lower(string(opt.mode))
    case "full"
        M = S2;
        if ~opt.includeDiag
            M(1:N+1:end) = NaN;
        end
    case "upper"
        k = opt.includeDiag*0 + (~opt.includeDiag); % 0 if includeDiag, 1 if not
        mask = triu(true(N), k);
        M = nan(N); M(mask) = S2(mask);
    case "lower"
        k = opt.includeDiag*0 + (~opt.includeDiag); % 0 if includeDiag, 1 if not
        mask = tril(true(N), -k);
        M = nan(N); M(mask) = S2(mask);
    otherwise
        error('plot_similarity:mode','Unknown mode.');
end

% Data range (ignore NaNs)
dataMin = min(M(~isnan(M)), [], 'all');
dataMax = max(M(~isnan(M)), [], 'all');

% Decide CLim
if ~isempty(opt.clim)
    climToUse = opt.clim;
elseif ~isempty(opt.center)
    % default symmetric if user set symmetric true, else auto to span data
    if isempty(opt.symmetric), opt.symmetric = true; end
    if opt.symmetric
        maxDev = max(opt.center - dataMin, dataMax - opt.center);
        climToUse = [opt.center - maxDev, opt.center + maxDev];
    else
        % auto pad so 'center' is midpoint (non-symmetric span)
        lowerDev = opt.center - dataMin;
        upperDev = dataMax - opt.center;
        if lowerDev > upperDev
            climToUse = [dataMin, dataMax + (lowerDev - upperDev)];
        else
            climToUse = [dataMin - (upperDev - lowerDev), dataMax];
        end
    end
else
    climToUse = [dataMin, dataMax];
end

% Plot
if strcmpi(opt.mode,'full') && opt.hideDiag
    % Replace diagonal with NaN (hidden, shows axes background color)
    M(1:N+1:end) = NaN;
end

figure;
imagesc(M, 'AlphaData', ~isnan(M));
% Overlay diagonal with user-defined color
if strcmpi(opt.mode,'full') && ~isempty(opt.diagColor)
    hold on;
    for i = 1:N
        plot(i,i,'s', ...
            'MarkerSize',8, ...
            'MarkerFaceColor',opt.diagColor, ...
            'MarkerEdgeColor',opt.diagColor);
    end
    hold off;
end
axis image; ax = gca; set(ax,'YDir','normal');
caxis(climToUse);

% Colormap
nCols = opt.nColors;
if ~isempty(opt.discreteLevels), nCols = max(2, round(opt.discreteLevels)); end

useCustomDiverging = ~isempty(opt.center) || ~isequal(opt.lowColor,[135 206 235]/255) ...
    || ~isequal(opt.midColor,[1 1 1]) || ~isequal(opt.highColor,[178 34 34]/255);

if useCustomDiverging && isempty(opt.clim)
    % Still fine: we'll compute fractions from climToUse derived above
end

if useCustomDiverging
    % Build asymmetric diverging map so midColor hits exactly 'center' within climToUse
    lo = climToUse(1); hi = climToUse(2); c0 = opt.center;
    assert(lo < hi, 'Invalid clim.');
    assert(c0 >= lo && c0 <= hi, 'center must lie within clim.');

    fracNeg = max(0, (c0 - lo) / (hi - lo));  % portion from lo -> c0
    n1 = max(1, round(nCols * fracNeg));
    n2 = max(1, nCols - n1);

    c1 = [linspace(opt.lowColor(1), opt.midColor(1), n1)', ...
          linspace(opt.lowColor(2), opt.midColor(2), n1)', ...
          linspace(opt.lowColor(3), opt.midColor(3), n1)'];
    c2 = [linspace(opt.midColor(1), opt.highColor(1), n2)', ...
          linspace(opt.midColor(2), opt.highColor(2), n2)', ...
          linspace(opt.midColor(3), opt.highColor(3), n2)'];

    cmap = [c1; c2];
    % if rounding produced n1+n2 ~= nCols, fix by trimming/padding
    if size(cmap,1) > nCols, cmap = cmap(1:nCols,:); end
    if size(cmap,1) < nCols
        cmap = [cmap; repmat(cmap(end,:), nCols-size(cmap,1), 1)];
    end
    colormap(ax, cmap);
else
    cmap = getColormap(opt.cmap, nCols);
    colormap(ax, cmap);
end

% Colorbar
if opt.colorbar
    cb = colorbar;
    if ~isempty(opt.cbarTicks)
        cb.Ticks = opt.cbarTicks;
    elseif ~isempty(opt.discreteLevels)
        cb.Ticks = linspace(climToUse(1), climToUse(2), min(opt.discreteLevels,10));
    end
end

title(opt.title);

% Ticks/labels
if ~isempty(opt.labels)
    labs = opt.labels(orderUsed);
    set(ax,'XTick',1:N,'XTickLabel',labs,'XTickLabelRotation',90);
    set(ax,'YTick',1:N,'YTickLabel',labs);
else
    set(ax,'XTick',[],'YTick',[]);
end
box on;

end % function

% ---------- helpers ----------
function cmap = getColormap(spec, n)
    if ischar(spec) || (isstring(spec) && isscalar(spec))
        name = char(spec);
        try
            cmap = feval(name, n);
        catch
            error('Unknown colormap: %s', name);
        end
    elseif isnumeric(spec) && size(spec,2)==3
        base = spec;
        xi = linspace(1, size(base,1), n);
        x  = 1:size(base,1);
        cmap = [interp1(x, base(:,1), xi, 'linear')', ...
                interp1(x, base(:,2), xi, 'linear')', ...
                interp1(x, base(:,3), xi, 'linear')'];
        cmap = max(min(cmap,1),0);
    else
        error('cmap must be a name or an Nx3 numeric array.');
    end
end
