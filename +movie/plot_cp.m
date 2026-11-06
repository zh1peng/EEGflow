function plot_cp(cp_results, varargin)
% PLOT_CP Visualizes results of a CP tensor decomposition.
%   This function creates a figure showing the spatial, temporal, and subject
%   factors for specified components from a CP decomposition.
%
%   It displays each component as a row in a figure, with three columns:
%   1. Scalp topography of the spatial factor (A).
%   2. Line plot of the temporal factor (B).
%   3. Bar plot of the subject loadings (C).
%
% Inputs:
%   cp_results (struct, REQUIRED)
%       The output struct from movie.run_cp. It must contain the fields
%       A, B, C, cp, chanlocs, and subjects.
%
% Name-Value Pair Arguments:
%   'components_to_plot' (numeric vector, default: 1:5)
%       A vector specifying which components to plot. If a single number `K`
%       is given, the top K components (ranked by lambda) will be shown.
%       If a vector is given, those specific components are plotted.
%
%   'sort_by_lambda' (logical, default: true)
%       If true, components are ranked by their lambda value (strength)
%       before plotting. If false, components are plotted in their original
%       numerical order (e.g., 1, 2, 3...). This is useful for plotting
%       a specific subset of components via 'components_to_plot'.
%
% Examples:
%   % Assume 'results' is the output from movie.run_cp(Out)
%
%   % Example 1: Default plot of the top 5 components
%   movie.plot_cp(results);
%
%   % Example 2: Plot the top 10 components
%   movie.plot_cp(results, 'components_to_plot', 10);
%
%   % Example 3: Plot specific components (e.g., 3, 5, and 8)
%   %            without sorting them by strength.
%   movie.plot_cp(results, 'components_to_plot', [3, 5, 8], 'sort_by_lambda', false);

%% ----------------------------
% 1) Parse Inputs
% -----------------------------
p = inputParser;
p.FunctionName = 'plot_cp';
addRequired(p, 'cp_results', @(x) isstruct(x) && all(isfield(x, {'A','B','C','cp','chanlocs','subjects'})));
addParameter(p, 'components_to_plot', 1:5, @isnumeric);
addParameter(p, 'sort_by_lambda', true, @islogical);

parse(p, cp_results, varargin{:});
opt = p.Results;

% Unpack data from the main struct
A = opt.cp_results.A;
B = opt.cp_results.B;
C = opt.cp_results.C;
cp = opt.cp_results.cp;
chanlocs = opt.cp_results.chanlocs;
subjects = opt.cp_results.subjects;

%% ----------------------------
% 2) Determine Components to Plot
% -----------------------------
lambda = cp.lambda(:);
R = numel(lambda);

if opt.sort_by_lambda
    [~, order] = sort(lambda, 'descend');
    if isscalar(opt.components_to_plot)
        K = min(opt.components_to_plot, R);
        plot_idx = order(1:K);
    else
        plot_idx = opt.components_to_plot;
        plot_idx = plot_idx(ismember(plot_idx, 1:R)); % Ensure valid indices
    end
else
    plot_idx = opt.components_to_plot;
    plot_idx = plot_idx(ismember(plot_idx, 1:R)); % Ensure valid indices
end

K = numel(plot_idx);
assert(K > 0, 'No valid components selected for plotting.');

%% ----------------------------
% 3) Prepare Plotting Assets
% -----------------------------
% Time vector
if isfield(opt.cp_results, 'tvec') && numel(opt.cp_results.tvec) == size(B, 1)
    t = opt.cp_results.tvec;
else
    t = 1:size(B, 1);
end

% Shared limits for comparability
B_plot = B(:, plot_idx);
C_plot = C(:, plot_idx);
yl_t = max(abs(B_plot), [], 'all'); yl_t = max(yl_t, eps); yl_t = [-yl_t yl_t];
yl_s = max(abs(C_plot), [], 'all'); yl_s = max(yl_s, eps); yl_s = [-yl_s yl_s];

% Sanitize subject labels
S = size(C, 1);
if isfield(opt.cp_results, 'SubjectPrefix')
    prefix = opt.cp_results.SubjectPrefix;
    labels = cellfun(@(s) strrep(s, prefix, ''), subjects, 'UniformOutput', false);
else
    labels = compose('S%%d', 1:S);
end

if S <= 30
    tick_idx = 1:S;
else
    tick_idx = unique(round(linspace(1, S, min(20, S))));
end
tick_labels = labels(tick_idx);

%% ----------------------------
% 4) Create Plot
% -----------------------------
figure('Name', sprintf('CP Components (Rank=%d)', R), 'Color', 'w');

for i = 1:K
    r = plot_idx(i);

    % Column 1: Topography
    subplot(K, 3, (i-1)*3 + 1);
    vals = A(:, r);
    clim = max(abs(vals));
    clim = max(clim, eps);
    topoplot(vals, chanlocs, 'electrodes', 'off', 'style', 'map', 'shading', 'flat');
    caxis([-clim, clim]);
    colorbar('eastoutside');
    title(sprintf('Comp %d (%s = %.3g)', r, char(955), lambda(r)));  % 955 = λ

    % Column 2: Temporal Factor
    subplot(K, 3, (i-1)*3 + 2);
    if isfield(opt.cp_results, 'is_tfr') && opt.cp_results.is_tfr
        % TFR data: Reshape and plot with imagesc
        F = opt.cp_results.minF;
        T = opt.cp_results.minT;
        fvec = opt.cp_results.fvec;
        tvec = opt.cp_results.tvec;
        
        B_reshaped = reshape(B(:, r), F, T);
        imagesc(tvec, fvec, B_reshaped);
        set(gca, 'ydir', 'normal'); % Put low freqs at bottom
        xlabel('Time (s)');
        ylabel('Frequency (Hz)');
        title('Freq-Time');
        colorbar('eastoutside');
        clim_t = max(abs(B_reshaped), [], 'all');
        caxis([-clim_t, clim_t]);
    else
        % Time-series data: Plot as a line
        plot(t, B(:, r), 'LineWidth', 1.2);
        xlim([t(1) t(end)]);
        ylim(yl_t);
        xlabel('Time (s) or Samples');
        ylabel('Loading');
        title('Temporal');
        grid on;
    end

    % Column 3: Subject Loadings
    subplot(K, 3, (i-1)*3 + 3);
    bar(C(:, r), 'EdgeColor', 'none');
    ylim(yl_s);
    xlim([0.5 S+0.5]);
    set(gca, 'XTick', tick_idx, 'XTickLabel', tick_labels, 'XTickLabelRotation', 90);
    ylabel('Loading');
    title('Subjects');
end

sgtitle(sprintf('CP Decomposition Components'), 'FontWeight', 'bold');

end
