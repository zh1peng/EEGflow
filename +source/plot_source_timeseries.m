function fig = plot_source_timeseries(src, varargin)
%PLOT_SOURCE_TIMESERIES Plot source/parcel virtual-channel waveforms.

    ip = inputParser;
    ip.addRequired('src', @isstruct);
    ip.addParameter('Signals', [], @(x) isempty(x) || isnumeric(x) || iscellstr(x) || isstring(x));
    ip.addParameter('Trials', [], @(x) isempty(x) || isnumeric(x));
    ip.addParameter('AverageTrials', true, @(x) islogical(x) && isscalar(x));
    ip.addParameter('Visible', 'off', @(s) ischar(s) || isstring(s));
    ip.addParameter('OutputFile', '', @(s) ischar(s) || isstring(s));
    ip.parse(src, varargin{:});
    R = ip.Results;

    if ~isfield(src, 'trial') || isempty(src.trial) || ~isfield(src, 'time')
        error('source:plot_source_timeseries:BadSource', 'src.trial and src.time are required.');
    end
    sigIdx = local_signal_idx(src, R.Signals);
    trIdx = R.Trials;
    if isempty(trIdx), trIdx = 1:numel(src.trial); end
    trIdx = trIdx(trIdx >= 1 & trIdx <= numel(src.trial));

    if R.AverageTrials
        X = zeros(numel(sigIdx), size(src.trial{trIdx(1)}, 2));
        for i = 1:numel(trIdx)
            X = X + double(src.trial{trIdx(i)}(sigIdx, :));
        end
        X = X / numel(trIdx);
        t = src.time{trIdx(1)};
    else
        X = double(src.trial{trIdx(1)}(sigIdx, :));
        t = src.time{trIdx(1)};
    end

    fig = figure('Visible', char(string(R.Visible)), 'Color', 'w');
    plot(t, X');
    xlabel('Time (s)');
    ylabel('Amplitude');
    title(sprintf('Source %s time series', local_get(src, 'level', '')));
    if numel(sigIdx) <= 12 && isfield(src, 'label')
        legend(src.label(sigIdx), 'Interpreter', 'none', 'Location', 'best');
    end

    outFile = char(string(R.OutputFile));
    if ~isempty(outFile)
        [outDir, ~, ~] = fileparts(outFile);
        if ~isempty(outDir) && ~isfolder(outDir), mkdir(outDir); end
        exportgraphics(fig, outFile, 'Resolution', 150);
    end
end

function idx = local_signal_idx(src, signals)
    if isempty(signals)
        idx = 1:min(numel(src.label), 8);
    elseif isnumeric(signals)
        idx = signals(:)';
    else
        labels = string(src.label(:));
        wanted = string(signals(:));
        [tf, idx] = ismember(wanted, labels);
        idx = idx(tf);
    end
    idx = idx(idx >= 1 & idx <= numel(src.label));
    if isempty(idx)
        error('source:plot_source_timeseries:NoSignals', 'No valid signals selected.');
    end
end

function v = local_get(s, field, default)
    v = default;
    if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
        v = s.(field);
    end
end
