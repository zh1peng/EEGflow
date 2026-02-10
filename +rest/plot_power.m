function [power_fig, topoplot_fig] = plot_power(res, varargin)
%PLOT_POWER Plot sensor-space PSD and band topographies (FieldTrip).
%
% Usage:
%   [fPsd, fTopo] = rest.plot_power(res);
%
% Input:
%   res : output struct from rest.compute_all_features (contains res.power,
%         res.peakfrequency, res.params.FreqBand)
%
% Name-value options:
%   'Visible'  : 'on'|'off' (default 'off')
%   'Title'    : char/string (default 'Power spectrum (electrode avg.)')
%   'FreqBand' : struct of bands (defaults to res.params.FreqBand)
%
% Notes:
% - The PSD plot style is inspired by DISCOVER-EEG (CC BY 4.0).

    ip = inputParser;
    ip.addRequired('res', @isstruct);
    ip.addParameter('Visible', 'off', @(s) ischar(s) || isstring(s));
    ip.addParameter('Title', 'Power spectrum (electrode avg.)', @(s) ischar(s) || isstring(s));
    ip.addParameter('FreqBand', struct(), @isstruct);
    ip.parse(res, varargin{:});
    R = ip.Results;

    % Resolve power struct + params.
    if isfield(res, 'power') && isstruct(res.power)
        power = res.power;
    elseif isfield(res, 'powspctrm') && isfield(res, 'freq')
        power = res;
    else
        error('rest:plot_power:BadInput', 'Expected res.power (FieldTrip freq struct).');
    end

    freqBand = R.FreqBand;
    if isempty(fieldnames(freqBand))
        if isfield(res, 'params') && isfield(res.params, 'FreqBand') && isstruct(res.params.FreqBand)
            freqBand = res.params.FreqBand;
        else
            error('rest:plot_power:MissingFreqBand', 'Provide FreqBand or res.params.FreqBand.');
        end
    end

    peakfrequency = [];
    if isfield(res, 'peakfrequency') && isstruct(res.peakfrequency)
        peakfrequency = res.peakfrequency;
    end

    freqNames = fieldnames(freqBand);

    % --- PSD figure ---
    avgpow = mean(double(power.powspctrm), 1, 'omitnan');
    f = double(power.freq(:).');

    power_fig = figure('Units', 'centimeters', 'Position', [0 0 12 7], ...
        'Visible', char(string(R.Visible)), 'Color', 'w');
    ax = axes(power_fig); %#ok<LAXES>
    hold(ax, 'on');

    c = lines(numel(freqNames));
    a = gobjects(numel(freqNames), 1);

    for iFreq = 1:numel(freqNames)
        lim = freqBand.(freqNames{iFreq});
        if ~isnumeric(lim) || numel(lim) ~= 2, continue; end
        idx = f >= lim(1) & f <= lim(2);
        if ~any(idx), continue; end
        a(iFreq) = area(ax, f(idx), avgpow(idx), ...
            'FaceColor', c(iFreq, :), 'FaceAlpha', 0.30, 'EdgeColor', 'none', ...
            'DisplayName', freqNames{iFreq});
    end

    plot(ax, f, avgpow, 'k', 'LineWidth', 1.25, 'DisplayName', 'PSD');

    % Peak frequency markers
    p = gobjects(0, 1);
    if isstruct(peakfrequency)
        if isfield(peakfrequency, 'localmax') && ~isempty(peakfrequency.localmax) && isfinite(peakfrequency.localmax)
            y = interp1(f, avgpow, double(peakfrequency.localmax), 'linear', 'extrap');
            p(end+1) = plot(ax, double(peakfrequency.localmax), y, 'v', 'MarkerSize', 6, ...
                'MarkerEdgeColor', [0.00 0.40 0.20], 'MarkerFaceColor', [0.00 0.40 0.20], ...
                'DisplayName', 'APF - max'); %#ok<AGROW>
        end
        if isfield(peakfrequency, 'cog') && ~isempty(peakfrequency.cog) && isfinite(peakfrequency.cog)
            y = interp1(f, avgpow, double(peakfrequency.cog), 'linear', 'extrap');
            p(end+1) = plot(ax, double(peakfrequency.cog), y, 'v', 'MarkerSize', 6, ...
                'MarkerEdgeColor', [0.60 0.75 0.12], 'MarkerFaceColor', [0.60 0.75 0.12], ...
                'DisplayName', 'APF - c.o.g.'); %#ok<AGROW>
        end
    end

    title(ax, char(string(R.Title)), 'Interpreter', 'none');
    ylabel(ax, 'Power (uV^2/Hz)');
    xlabel(ax, 'Frequency (Hz)');
    box(ax, 'off');
    grid(ax, 'on');
    legend(ax, 'show', 'Location', 'eastoutside', 'Color', 'none', 'Interpreter', 'none');

    hold(ax, 'off');

    % --- Topoplots per band ---
    topoplot_fig = [];
    if exist('ft_topoplotER', 'file') ~= 2
        return;
    end

    nBand = numel(freqNames);
    nCol = ceil(sqrt(nBand));
    nRow = ceil(nBand / nCol);

    topoplot_fig = figure('Units', 'centimeters', 'Position', [0 0 11 10], ...
        'Visible', char(string(R.Visible)), 'Color', 'w');
    tcl = tiledlayout(topoplot_fig, nRow, nCol, 'TileSpacing', 'compact', 'Padding', 'compact');

    for iFreq = 1:nBand
        band = freqNames{iFreq};
        lim = freqBand.(band);
        if ~isnumeric(lim) || numel(lim) ~= 2
            continue;
        end

        ax = nexttile(tcl, iFreq);
        cfg = [];
        cfg.xlim = lim;
        cfg.comment = 'no';
        cfg.interactive = 'no';
        cfg.figure = ax;
        ft_topoplotER(cfg, power);
        title(ax, band, 'Interpreter', 'none');
        colorbar(ax);
    end
end

