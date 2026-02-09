function state = tf_plot_band_timecourse(state, args, meta)
%TF_PLOT_BAND_TIMECOURSE Plot ROI/channel band-averaged TF timecourse.
%
% Args (args struct):
%   group (char|string)      required group name in state.Results.GA_TFD
%   condition (char|string)  required condition name in group GA
%   target (char|string)     ROI name or channel label
%   band (char|string)       frequency band name in state.Selection.FreqBands
%   out_file (char|string)   optional path to save figure
%   visible (logical)        default false
%   line_width (numeric)     default 2
%
% Returns:
%   state (unchanged)
%
% Notes:
%   Uses GA_TFD.tfd in [chan x freq x time] layout and averages across
%   selected channels and band frequencies to produce one timecourse.

    if nargin < 2 || isempty(args), args = struct(); end
    if nargin < 3 || isempty(meta), meta = struct(); end

    req = {'group', 'condition', 'target', 'band'};
    for i = 1:numel(req)
        if ~isfield(args, req{i}) || isempty(args.(req{i}))
            error('Missing required arg: %s', req{i});
        end
    end
    if ~isfield(args, 'out_file'), args.out_file = ''; end
    if ~isfield(args, 'visible'), args.visible = false; end
    if ~isfield(args, 'line_width'), args.line_width = 2; end

    if isfield(meta, 'validate_only') && meta.validate_only
        return;
    end

    state_check(state, 'GA_TFD');

    group = char(string(args.group));
    condition = char(string(args.condition));
    target = char(string(args.target));
    band = char(string(args.band));

    if ~isfield(state.Selection, 'FreqBands') || ~isfield(state.Selection.FreqBands, band)
        error('Band "%s" is not defined in state.Selection.FreqBands.', band);
    end
    if ~isfield(state.Results.GA_TFD, group) || ~isfield(state.Results.GA_TFD.(group), condition)
        error('GA_TFD missing for group/condition: %s/%s', group, condition);
    end

    [ch_idx, title_str] = state_get_indices(state, target);
    ga = state.Results.GA_TFD.(group).(condition);
    fband = state.Selection.FreqBands.(band);
    freqs = ga.freqs;
    times = ga.times;

    fmask = freqs >= fband(1) & freqs <= fband(2);
    if ~any(fmask)
        error('No frequencies in GA_TFD fall inside band "%s" [%g %g] Hz.', ...
            band, fband(1), fband(2));
    end

    data = ga.tfd; % [chan x f x t]
    band_tc = squeeze(mean(mean(data(ch_idx, fmask, :), 1), 2)); % [t]

    vis = 'off';
    if args.visible, vis = 'on'; end
    fig = figure('Visible', vis);
    plot(times, band_tc, 'LineWidth', args.line_width);
    grid on;
    xlabel('Time (ms)');
    ylabel('Power (a.u.)');
    title(sprintf('%s - %s (%s band, %s)', group, condition, band, title_str));

    if ~isempty(args.out_file)
        saveas(fig, args.out_file);
        close(fig);
    end
end

