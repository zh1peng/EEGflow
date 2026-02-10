function fig_save(fig, saveBase, formats, resolution)
%FIG_SAVE Save a figure to multiple formats using exportgraphics where possible.
%
% Inputs:
%   fig        : figure handle
%   saveBase   : path without extension
%   formats    : cellstr or string array, e.g., {'png','pdf'}
%   resolution : numeric dpi for raster outputs (png)

    if nargin < 1 || isempty(fig) || ~ishandle(fig)
        error('analysis:fig_save:BadFig', 'Invalid figure handle.');
    end
    if nargin < 2 || isempty(saveBase)
        return;
    end
    if nargin < 3 || isempty(formats)
        formats = {'png','pdf'};
    end
    if nargin < 4 || isempty(resolution)
        resolution = 300;
    end

    saveBase = char(string(saveBase));
    outDir = fileparts(saveBase);
    if ~isempty(outDir) && ~isfolder(outDir)
        mkdir(outDir);
    end

    if isstring(formats), formats = cellstr(formats); end
    if ~iscell(formats), formats = {formats}; end

    for i = 1:numel(formats)
        fmt = char(string(formats{i}));
        fmt = lower(strrep(fmt, '.', ''));
        if isempty(fmt)
            continue;
        end
        outFile = sprintf('%s.%s', saveBase, fmt);

        try
            switch fmt
                case 'png'
                    exportgraphics(fig, outFile, 'Resolution', resolution);
                case {'pdf','eps'}
                    exportgraphics(fig, outFile, 'ContentType', 'vector');
                case {'svg'}
                    exportgraphics(fig, outFile, 'ContentType', 'vector');
                otherwise
                    % Fallback: let exportgraphics try
                    exportgraphics(fig, outFile);
            end
        catch
            % Fallback for older MATLAB or edge cases.
            try
                switch fmt
                    case 'png'
                        print(fig, outFile, '-dpng', sprintf('-r%d', resolution));
                    case 'pdf'
                        print(fig, outFile, '-dpdf', '-painters');
                    case 'eps'
                        print(fig, outFile, '-depsc', '-painters');
                    otherwise
                        print(fig, outFile, ['-d' fmt]);
                end
            catch ME
                warning('analysis:fig_save:SaveFailed', 'Failed saving %s (%s).', outFile, ME.message);
            end
        end
    end
end

