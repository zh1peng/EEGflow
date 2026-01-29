function state_imagesc_tfr(times, freqs, data, opts)
%STATE_IMAGESC_TFR Plot a TFR heatmap with optional ranges/mask.
    imagesc(times, freqs, data);
    axis xy;
    xlabel('Time (ms)');
    ylabel('Frequency (Hz)');
    colorbar;
    if isfield(opts, 'x_range') && ~isempty(opts.x_range), xlim(opts.x_range); end
    if isfield(opts, 'freq_range') && ~isempty(opts.freq_range), ylim(opts.freq_range); end
    if isfield(opts, 'color_range') && ~isempty(opts.color_range), caxis(opts.color_range); end

    if isfield(opts, 'mask') && ~isempty(opts.mask)
        hold on;
        M = logical(opts.mask);
        if any(M(:))
            contour(times, freqs, M, [1 1], 'LineColor', 'k', 'LineWidth', 1.2);
        end
    end
end
