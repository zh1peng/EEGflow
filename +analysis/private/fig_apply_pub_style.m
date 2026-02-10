function fig_apply_pub_style(fig)
%FIG_APPLY_PUB_STYLE Apply consistent "publication-ready" styling to a figure.

    if nargin < 1 || isempty(fig) || ~ishandle(fig)
        return;
    end

    try
        set(fig, 'Color', 'w');
        set(fig, 'InvertHardcopy', 'off');
    catch
    end

    % Text interpreter: show underscores literally by default.
    try
        set(fig, 'DefaultTextInterpreter', 'none');
        set(fig, 'DefaultLegendInterpreter', 'none');
    catch
    end

    ax = findall(fig, 'Type', 'axes');
    for k = 1:numel(ax)
        try
            set(ax(k), ...
                'FontName', 'Arial', ...
                'FontSize', 11, ...
                'LineWidth', 1, ...
                'TickDir', 'out', ...
                'Box', 'off', ...
                'XColor', [0.15 0.15 0.15], ...
                'YColor', [0.15 0.15 0.15]);
        catch
        end

        % Axes tick label interpreter is version-dependent.
        try
            if isprop(ax(k), 'TickLabelInterpreter')
                ax(k).TickLabelInterpreter = 'none';
            end
        catch
        end
    end

    txt = findall(fig, 'Type', 'text');
    for k = 1:numel(txt)
        try
            set(txt(k), 'Interpreter', 'none', 'FontName', 'Arial');
        catch
        end
    end

    lgd = findall(fig, 'Type', 'legend');
    for k = 1:numel(lgd)
        try
            set(lgd(k), 'Interpreter', 'none', 'Box', 'off');
        catch
        end
    end
end

