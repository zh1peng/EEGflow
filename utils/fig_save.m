function fig_save(fig, outFile, varargin)
%FIG_SAVE Save a figure to disk (best-effort) using exportgraphics/print.
%
% Usage:
%   fig_save(fig, 'out.png');
%   fig_save(fig, 'out.pdf');
%   fig_save(fig, 'out.png', 'Resolution', 150);
%
% Name-value options:
%   'Resolution'     : dpi for raster outputs (default 150)
%   'DeleteExisting' : delete outFile first if it exists (default true)

    ip = inputParser;
    ip.addRequired('fig');
    ip.addRequired('outFile', @(s) ischar(s) || isstring(s));
    ip.addParameter('Resolution', 150, @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    ip.addParameter('DeleteExisting', true, @(x) islogical(x) && isscalar(x));
    ip.parse(fig, outFile, varargin{:});
    R = ip.Results;

    fig = R.fig;
    if isempty(fig) || ~(ishandle(fig) || (exist('isgraphics', 'file') ~= 0 && isgraphics(fig)))
        return;
    end

    outFile = char(string(R.outFile));
    if isempty(outFile)
        return;
    end

    outDir = fileparts(outFile);
    if ~isempty(outDir) && ~isfolder(outDir)
        mkdir(outDir);
    end

    if R.DeleteExisting && exist(outFile, 'file') == 2
        try, delete(outFile); catch, end %#ok<CTCH>
    end

    % Suppress a noisy MATLAB graphics callback warning that can appear during
    % export when ColorBar listeners are updated.
    wCb = warning('query', 'MATLAB:callback:error');
    warning('off', 'MATLAB:callback:error');
    cbCleanup = onCleanup(@() warning(wCb.state, 'MATLAB:callback:error')); %#ok<NASGU>

    % Flush pending graphics updates (helps avoid exportgraphics/print issues).
    try, drawnow; catch, end %#ok<CTCH>

    [~, ~, ext] = fileparts(outFile);
    ext = lower(strrep(ext, '.', ''));

    try
        if exist('exportgraphics', 'file') ~= 0
            switch ext
                case 'png'
                    exportgraphics(fig, outFile, 'Resolution', double(R.Resolution));
                case {'pdf','eps','svg'}
                    exportgraphics(fig, outFile, 'ContentType', 'vector');
                otherwise
                    exportgraphics(fig, outFile);
            end
        else
            local_print_fallback(fig, outFile, ext, double(R.Resolution));
        end
    catch
        local_print_fallback(fig, outFile, ext, double(R.Resolution));
    end
end

function local_print_fallback(fig, outFile, ext, resolution)
    % print() needs a figure handle; exportgraphics can handle axes too.
    if ~(ishandle(fig) && strcmp(get(fig, 'Type'), 'figure')) %#ok<GFLD>
        try
            fig = ancestor(fig, 'figure');
        catch
            return;
        end
    end
    if isempty(fig) || ~ishandle(fig)
        return;
    end

    try
        switch ext
            case 'png'
                print(fig, outFile, '-dpng', sprintf('-r%d', resolution));
            case 'pdf'
                print(fig, outFile, '-dpdf', '-painters');
            case 'eps'
                print(fig, outFile, '-depsc', '-painters');
            otherwise
                if isempty(ext)
                    print(fig, outFile, '-dpng', sprintf('-r%d', resolution));
                else
                    print(fig, outFile, ['-d' ext]);
                end
        end
    catch ME
        warning('fig_save:SaveFailed', 'Failed saving %s (%s).', outFile, ME.message);
    end
end
