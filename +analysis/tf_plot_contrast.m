function state = tf_plot_contrast(state, args, meta)
%TF_PLOT_CONTRAST Plot TF contrast map with optional significance mask.
%
% Args:
%   contrast (char)  contrast name
%   roi (char)       ROI name (optional)
%   x_range, freq_range, color_range
%   mask (logical)   optional [freq x time] mask

    if nargin < 2, args = struct(); end
    if ~isfield(args, 'roi'), args.roi = ''; end
    if nargin >= 3 && isfield(meta, 'validate_only') && meta.validate_only
        return;
    end

    state_check(state, 'Contrasts');
    cname = args.contrast;
    if ~isfield(state.Results.Contrasts, cname)
        error('Contrast "%s" not found.', cname);
    end
    C = state.Results.Contrasts.(cname);

    [freqs, times] = state_get_tf_axes(state, {}, '', C);

    if isfield(C, 'tfd')
        data = C.tfd;
    elseif isfield(C, 'maps')
        data = mean(C.maps, 4);
    elseif isfield(C, 'pos_maps') && isfield(C, 'neg_maps')
        data = mean(C.pos_maps, 4) - mean(C.neg_maps, 4);
    else
        error('Contrast "%s" has no TF data.', cname);
    end

    if ~isempty(args.roi)
        [ch_idx, title_str] = state_get_indices(state, args.roi);
        plot_data = squeeze(mean(data(ch_idx, :, :), 1));
    else
        title_str = 'AllCh';
        plot_data = squeeze(mean(data, 1));
    end

    if ~isfield(args, 'mask') || isempty(args.mask)
        args.mask = [];
    end

    figure('Name', ['TF Contrast ' cname]);
    state_imagesc_tfr(times, freqs, plot_data, args);
    title(sprintf('Contrast: %s (%s)', cname, title_str), 'Interpreter', 'none');
end
