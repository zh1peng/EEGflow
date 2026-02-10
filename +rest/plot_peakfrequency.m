function fig = plot_peakfrequency(res, varargin)
%PLOT_PEAKFREQUENCY Plot alpha-band peak frequency on the average PSD.
%
% Usage:
%   fig = rest.plot_peakfrequency(res);
%
% Input:
%   res : output struct from rest.compute_all_features (needs res.power,
%         res.peakfrequency, res.params.FreqBand.alpha)

    ip = inputParser;
    ip.addRequired('res', @isstruct);
    ip.addParameter('Visible', 'off', @(s) ischar(s) || isstring(s));
    ip.addParameter('Title', '', @(s) ischar(s) || isstring(s));
    ip.parse(res, varargin{:});
    R = ip.Results;

    if ~isfield(res, 'power') || ~isstruct(res.power)
        error('rest:plot_peakfrequency:MissingPower', 'res.power is required.');
    end
    if ~isfield(res, 'peakfrequency') || ~isstruct(res.peakfrequency)
        error('rest:plot_peakfrequency:MissingPeak', 'res.peakfrequency is required.');
    end
    if ~isfield(res, 'params') || ~isfield(res.params, 'FreqBand') || ~isfield(res.params.FreqBand, 'alpha')
        error('rest:plot_peakfrequency:MissingAlphaBand', 'res.params.FreqBand.alpha is required.');
    end

    power = res.power;
    pf = res.peakfrequency;

    avgpow = mean(double(power.powspctrm), 1, 'omitnan');
    f = double(power.freq(:).');
    lim = res.params.FreqBand.alpha;
    idx = f >= lim(1) & f <= lim(2);

    fig = figure('Color', 'w', 'Visible', char(string(R.Visible)));
    ax = axes(fig); %#ok<LAXES>
    plot(ax, f(idx), avgpow(idx), 'k', 'LineWidth', 1.25);
    hold(ax, 'on');

    if isfield(pf, 'localmax') && ~isempty(pf.localmax) && isfinite(pf.localmax)
        y = interp1(f, avgpow, double(pf.localmax), 'linear', 'extrap');
        plot(ax, double(pf.localmax), y, 'v', 'MarkerSize', 8, ...
            'MarkerEdgeColor', [0.00 0.40 0.20], 'MarkerFaceColor', [0.00 0.40 0.20]);
    end
    if isfield(pf, 'cog') && ~isempty(pf.cog) && isfinite(pf.cog)
        y = interp1(f, avgpow, double(pf.cog), 'linear', 'extrap');
        plot(ax, double(pf.cog), y, 'v', 'MarkerSize', 8, ...
            'MarkerEdgeColor', [0.60 0.75 0.12], 'MarkerFaceColor', [0.60 0.75 0.12]);
    end

    ylabel(ax, 'Power (uV^2/Hz)');
    xlabel(ax, 'Frequency (Hz)');
    box(ax, 'off');
    grid(ax, 'on');

    ttl = char(string(R.Title));
    if isempty(ttl)
        if isfield(res, 'subid') && ~isempty(res.subid)
            ttl = sprintf('Peak frequency | %s', char(string(res.subid)));
        else
            ttl = 'Peak frequency';
        end
    end
    title(ax, ttl, 'Interpreter', 'none');

    % Fake legend handles for consistent labeling.
    q = gobjects(0, 1);
    qName = {};
    q(end+1) = plot(ax, nan, nan, 'v', 'MarkerSize', 8, ...
        'MarkerEdgeColor', [0.00 0.40 0.20], 'MarkerFaceColor', [0.00 0.40 0.20]); %#ok<AGROW>
    qName{end+1} = 'Maximum peak'; %#ok<AGROW>
    q(end+1) = plot(ax, nan, nan, 'v', 'MarkerSize', 8, ...
        'MarkerEdgeColor', [0.60 0.75 0.12], 'MarkerFaceColor', [0.60 0.75 0.12]); %#ok<AGROW>
    qName{end+1} = 'Center of gravity'; %#ok<AGROW>
    legend(ax, q, qName, 'Location', 'southeast', 'Color', 'none', 'Interpreter', 'none');

    hold(ax, 'off');
end

