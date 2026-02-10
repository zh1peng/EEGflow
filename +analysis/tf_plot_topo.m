function state = tf_plot_topo(state, args, meta)
%TF_PLOT_TOPO Plot topography from TF band x time window.
%
% Args:
%   band (char)       name in state.Selection.FreqBands
%   window (char)     name in state.Selection.TimeWindows
%   group (char)      group name (for GA_TFD)
%   condition (char)  condition name (for GA_TFD)
%   contrast (char)   contrast name (optional, overrides group/condition)

    if nargin < 2, args = struct(); end
    if nargin >= 3 && isfield(meta, 'validate_only') && meta.validate_only
        return;
    end
    if ~exist('topoplot', 'file')
        error('topoplot not found. Ensure EEGLAB is on path.');
    end

    state_check(state);

    if ~isfield(args, 'band') || ~isfield(args, 'window')
        error('band and window are required.');
    end
    if ~isfield(state.Selection, 'FreqBands') || ~isfield(state.Selection.FreqBands, args.band)
        error('Band "%s" not found.', args.band);
    end
    if ~isfield(state.Selection, 'TimeWindows') || ~isfield(state.Selection.TimeWindows, args.window)
        error('Window "%s" not found.', args.window);
    end

    fband = state.Selection.FreqBands.(args.band);
    twin = state.Selection.TimeWindows.(args.window);
    [freqs, times] = resolve_tf_axes(state, args);
    fmask = freqs >= fband(1) & freqs <= fband(2);
    tmask = times >= twin(1) & times <= twin(2);

    if isfield(args, 'contrast') && ~isempty(args.contrast)
        C = state.Results.Contrasts.(args.contrast);
        if isfield(C, 'tfd')
            data = C.tfd;
        elseif isfield(C, 'maps')
            data = mean(C.maps, 4);
        elseif isfield(C, 'pos_maps') && isfield(C, 'neg_maps')
            data = mean(C.pos_maps, 4) - mean(C.neg_maps, 4);
        else
            error('Contrast "%s" has no TF data.', args.contrast);
        end
        topo = squeeze(mean(mean(data(:, fmask, tmask), 2), 3));
        ttl = sprintf('TF Topo: %s (%s, %s)', args.contrast, args.band, args.window);
    else
        if ~isfield(args, 'group') || ~isfield(args, 'condition')
            error('group and condition required for GA_TFD topography.');
        end
        ga = state.Results.GA_TFD.(args.group).(args.condition).tfd;
        topo = squeeze(mean(mean(ga(:, fmask, tmask), 2), 3));
        ttl = sprintf('TF Topo: %s-%s (%s, %s)', args.group, args.condition, args.band, args.window);
    end

    figure('Name', ttl);
    topoplot(topo, state.Dataset.chanlocs);
    title(ttl, 'Interpreter', 'none');
    cb = colorbar;
    if isprop(cb, 'TickLabelInterpreter')
        set(cb, 'TickLabelInterpreter', 'none');
    end
end

function [freqs, times] = resolve_tf_axes(state, args)
    freqs = []; times = [];
    if isfield(state.Dataset.data, 'meta')
        meta = state.Dataset.data.meta;
        if isfield(meta, 'freqs'), freqs = meta.freqs; end
        if isfield(meta, 'times'), times = meta.times; end
    end
    if ~isempty(freqs) && ~isempty(times)
        return;
    end
    if isfield(args, 'contrast') && ~isempty(args.contrast)
        C = state.Results.Contrasts.(args.contrast);
        if isfield(C, 'freqs'), freqs = C.freqs; end
        if isfield(C, 'times'), times = C.times; end
    end
    if isempty(freqs) || isempty(times)
        error('TF axes (freqs/times) not found.');
    end
end
