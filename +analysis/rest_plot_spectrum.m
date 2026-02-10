function fig = rest_plot_spectrum(power, varargin)
%REST_PLOT_SPECTRUM Publication-ready spectrum plot for resting-state PSD.
%
% Usage:
%   fig = analysis.rest_plot_spectrum(power, 'SaveBase', 'out/psd');
%
% Inputs:
%   power : FieldTrip freq struct with fields .freq and .powspctrm (chan x freq)
%
% Name-value options:
%   'PowerOsc'       : FieldTrip freq struct (aperiodic-removed / flattened), optional
%   'PeakFrequency'  : struct with fields .localmax and/or .cog, optional
%   'FreqBand'       : struct of bands, optional (e.g., struct('alpha',[8 12]))
%   'Title'          : char/string
%   'FreqLim'        : [fmin fmax] (default [1 45])
%   'SaveBase'       : base path without extension; when empty, no save
%   'Formats'        : cellstr extensions, default {'png','pdf'}
%   'Visible'        : 'on'|'off' (default 'off')
%   'Resolution'     : dpi for PNG (default 300)

    ip = inputParser;
    ip.addRequired('power', @isstruct);
    ip.addParameter('PowerOsc', [], @(x) isempty(x) || isstruct(x));
    ip.addParameter('PeakFrequency', [], @(x) isempty(x) || isstruct(x));
    ip.addParameter('FreqBand', struct(), @isstruct);
    ip.addParameter('Title', '', @(s) ischar(s) || isstring(s));
    ip.addParameter('FreqLim', [1 45], @(x) isnumeric(x) && numel(x) == 2);
    ip.addParameter('SaveBase', '', @(s) ischar(s) || isstring(s));
    ip.addParameter('Formats', {'png','pdf'}, @(x) iscellstr(x) || isstring(x));
    ip.addParameter('Visible', 'off', @(s) ischar(s) || isstring(s));
    ip.addParameter('Resolution', 300, @(x) isnumeric(x) && isscalar(x) && x > 0);
    ip.parse(power, varargin{:});
    R = ip.Results;

    freq = double(power.freq(:).');
    P = double(power.powspctrm);
    if ndims(P) ~= 2 || size(P, 2) ~= numel(freq)
        error('analysis:rest_plot_spectrum:BadInput', 'power.powspctrm must be nChan x nFreq and match power.freq.');
    end

    avg = mean(P, 1, 'omitnan');
    y = 10 * log10(max(avg, eps));

    hasOsc = ~isempty(R.PowerOsc) && isfield(R.PowerOsc, 'powspctrm') && isfield(R.PowerOsc, 'freq');
    if hasOsc
        Po = double(R.PowerOsc.powspctrm);
        fo = double(R.PowerOsc.freq(:).');
        if ~isequal(size(Po, 2), numel(fo)) || ~isequal(fo, freq)
            % best-effort: allow different freq vectors via interpolation
            avgOsc = mean(Po, 1, 'omitnan');
            yOsc = interp1(fo, 10*log10(max(avgOsc, eps)), freq, 'linear', 'extrap');
        else
            avgOsc = mean(Po, 1, 'omitnan');
            yOsc = 10 * log10(max(avgOsc, eps));
        end
    end

    fig = figure('Color', 'w', 'Visible', char(string(R.Visible)));
    tl = tiledlayout(fig, 1 + double(hasOsc), 1, 'TileSpacing', 'compact', 'Padding', 'compact');

    ax1 = nexttile(tl);
    hold(ax1, 'on');
    plot(ax1, freq, y, 'LineWidth', 1.75, 'Color', [0.10 0.10 0.10]);
    local_maybe_band_patch(ax1, R.FreqBand, 'alpha', [0.85 0.90 1.00]);
    local_maybe_peak_lines(ax1, R.PeakFrequency);
    hold(ax1, 'off');
    grid(ax1, 'on');
    xlabel(ax1, 'Frequency (Hz)');
    ylabel(ax1, 'Power (dB)');
    xlim(ax1, double(R.FreqLim));
    title(ax1, char(string(R.Title)), 'Interpreter', 'none');

    if hasOsc
        ax2 = nexttile(tl);
        hold(ax2, 'on');
        plot(ax2, freq, yOsc, 'LineWidth', 1.75, 'Color', [0.00 0.35 0.70]);
        yline(ax2, 0, ':', 'Color', [0.5 0.5 0.5], 'LineWidth', 1);
        local_maybe_band_patch(ax2, R.FreqBand, 'alpha', [0.85 0.90 1.00]);
        hold(ax2, 'off');
        grid(ax2, 'on');
        xlabel(ax2, 'Frequency (Hz)');
        ylabel(ax2, 'Flattened (dB)');
        xlim(ax2, double(R.FreqLim));
        title(ax2, 'Aperiodic-Removed Spectrum', 'Interpreter', 'none');
    end

    fig_apply_pub_style(fig);

    saveBase = char(string(R.SaveBase));
    if ~isempty(saveBase)
        fig_save(fig, saveBase, R.Formats, R.Resolution);
    end
end

function local_maybe_band_patch(ax, freqBand, bandName, faceColor)
    if ~isstruct(freqBand) || ~isfield(freqBand, bandName)
        return;
    end
    lim = freqBand.(bandName);
    if ~isnumeric(lim) || numel(lim) ~= 2
        return;
    end
    yl = ylim(ax);
    x1 = lim(1);
    x2 = lim(2);
    patch(ax, [x1 x2 x2 x1], [yl(1) yl(1) yl(2) yl(2)], faceColor, ...
        'FaceAlpha', 0.25, 'EdgeColor', 'none');
    uistack(findobj(ax, 'Type', 'line'), 'top');
end

function local_maybe_peak_lines(ax, peakfrequency)
    if ~isstruct(peakfrequency)
        return;
    end
    if isfield(peakfrequency, 'localmax') && ~isempty(peakfrequency.localmax) && isfinite(peakfrequency.localmax)
        xline(ax, double(peakfrequency.localmax), '--', 'LocalMax', ...
            'LabelOrientation', 'horizontal', 'LineWidth', 1.25, ...
            'Color', [0.80 0.20 0.20], 'Interpreter', 'none');
    end
    if isfield(peakfrequency, 'cog') && ~isempty(peakfrequency.cog) && isfinite(peakfrequency.cog)
        xline(ax, double(peakfrequency.cog), '--', 'CoG', ...
            'LabelOrientation', 'horizontal', 'LineWidth', 1.25, ...
            'Color', [0.20 0.60 0.20], 'Interpreter', 'none');
    end
end
