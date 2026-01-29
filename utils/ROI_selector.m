function selected_labels = ROI_selector(inputData, varargin)
    % ROI_SELECTOR Interactive topoplot channel selector.
    % 
    % Features:
    %   - Shows the code-ready string {'Fz','Cz'...} in the title in real-time.
    %   - Automatically copies that string to clipboard when finished.
    % 
    % Usage:
    %   labels = ROI_selector(EEG);
    %   labels = ROI_selector(chanlocs);

    % ---- 1. Input Parsing ----
    p = inputParser;
    addRequired(p, 'inputData');
    addParameter(p, 'show_labels', true, @islogical);
    addParameter(p, 'label_fontsize', 8, @isnumeric);
    addParameter(p, 'marker_size', 6, @isnumeric);
    addParameter(p, 'title', 'Drag to select. Enter/Right-Click to finish.', @ischar);
    parse(p, inputData, varargin{:});

    % ---- 2. Extract Chanlocs ----
    chanlocs = [];
    if isstruct(inputData) && isfield(inputData, 'labels'), chanlocs = inputData;
    elseif isstruct(inputData) && isfield(inputData, 'chanlocs'), chanlocs = inputData.chanlocs;
    elseif isobject(inputData)
        if isprop(inputData, 'Dataset') && ~isempty(inputData.Dataset)
            ds = inputData.Dataset;
            if isstruct(ds) && isfield(ds,'chanlocs'), chanlocs = ds.chanlocs;
            elseif isprop(ds,'chanlocs'), chanlocs = ds.chanlocs;
            elseif isstruct(ds) && isfield(ds,'EEG'), chanlocs = ds.EEG.chanlocs;
            end
        elseif isprop(inputData, 'chanlocs')
            chanlocs = inputData.chanlocs;
        end
    end

    if isempty(chanlocs), error('Could not find valid chanlocs.'); end
    if ~exist('topoplot','file'), error('EEGLAB function topoplot() missing.'); end

    % ---- 3. Setup Figure ----
    nChan  = numel(chanlocs);
    labels = {chanlocs.labels};
    dummy  = zeros(nChan,1);

    fig = figure('Position', [100 100 600 600], 'Name', 'ROI Selector', ...
                 'NumberTitle', 'off', 'MenuBar', 'none', 'ToolBar', 'none');
    ax = axes('Parent', fig); 

    if p.Results.show_labels
        elec_mode = 'labels';
    else
        elec_mode = 'on';
    end

    topoplot(dummy, chanlocs, 'style','blank', ...
        'electrodes', elec_mode, ...
        'whitebk','on', ...
        'efontsize', p.Results.label_fontsize, ...
        'emarker', {'o','k',p.Results.marker_size,1});
    
    title(ax, p.Results.title, 'Interpreter', 'none');
    axis(ax, 'equal'); 

    % ---- 4. Robust Coordinate Extraction ----
    x_elec = nan(1, nChan);
    y_elec = nan(1, nChan);
    found = false;

    % Method A: Scrape from plot
    hLines = findall(ax, 'Type','line');
    for k = 1:numel(hLines)
        if strcmp(get(hLines(k), 'Marker'), 'o')
            xd = get(hLines(k), 'XData');
            yd = get(hLines(k), 'YData');
            if numel(xd) == nChan
                x_elec = xd(:)'; y_elec = yd(:)'; found = true;
                break;
            end
        end
    end
    
    % Method B: Fallback
    if ~found
        try 
            th_cell = {chanlocs.theta};
            rd_cell = {chanlocs.radius};
            th_cell(cellfun(@isempty, th_cell)) = {NaN};
            rd_cell(cellfun(@isempty, rd_cell)) = {NaN};
            [y_elec, x_elec] = pol2cart(cell2mat(th_cell) * pi/180, cell2mat(rd_cell));
            x_elec = x_elec(:)'; y_elec = y_elec(:)';
        catch
            warning('Coordinate extraction failed.');
        end
    end

    if numel(x_elec) ~= nChan
        x_elec = nan(1, nChan); y_elec = nan(1, nChan);
    end

    valid = isfinite(x_elec) & isfinite(y_elec);

    % ---- 5. Interaction ----
    hold(ax,'on');
    hSel = plot(ax, nan, nan, 'ro', 'LineWidth', 2, 'MarkerSize', p.Results.marker_size + 6);
    selected_idx = false(1, nChan);
    
    setappdata(fig, 'isFinished', false);
    fig.WindowButtonDownFcn = @onMouseDown;
    fig.KeyPressFcn         = @onKeyPress;

    uiwait(fig);

    % ---- Return ----
    if ishandle(fig), delete(fig); end
    sel_indices = find(selected_idx);
    selected_labels = labels(sel_indices);

    % ---------------- Nested Functions ----------------
    function onMouseDown(~, ~)
        if getappdata(fig, 'isFinished'); return; end
        if strcmpi(get(fig, 'SelectionType'), 'alt'), finish(); return; end
        if ~strcmpi(get(fig, 'SelectionType'), 'normal'), return; end

        p1 = get(ax, 'CurrentPoint'); p1 = p1(1, 1:2);
        rbbox; 
        p2 = get(ax, 'CurrentPoint'); p2 = p2(1, 1:2);

        xMin = min(p1(1), p2(1)); xMax = max(p1(1), p2(1));
        yMin = min(p1(2), p2(2)); yMax = max(p1(2), p2(2));

        inBox = valid & (x_elec >= xMin) & (x_elec <= xMax) & (y_elec >= yMin) & (y_elec <= yMax);
        
        if any(inBox)
            selected_idx(inBox) = true; 
            updateVisuals();
        end
    end

    function onKeyPress(~, evt)
        switch lower(evt.Key)
            case {'return','enter'}, finish();
            case 'c', performCopy();
            case 'r', selected_idx(:) = false; updateVisuals();
        end
    end

    function updateVisuals()
        sel = find(selected_idx & valid);
        set(hSel, 'XData', x_elec(sel), 'YData', y_elec(sel));
        
        % Generate the copy-paste string
        str = formatLabelCell(labels(sel));
        
        % Truncate for display if it gets too huge for the title
        displayStr = str;
        if length(displayStr) > 60
            displayStr = [displayStr(1:57) '...}'];
        end
        
        % Real-time title update
        tString = {sprintf('Selected (%d):', numel(sel)), displayStr};
        title(ax, tString, 'Interpreter', 'none', 'FontSize', 10);
    end

    function finish()
        performCopy(); % Auto-copy on exit
        setappdata(fig, 'isFinished', true);
        uiresume(fig);
    end

    function performCopy()
        sel = find(selected_idx);
        if isempty(sel), return; end
        str = formatLabelCell(labels(sel));
        clipboard('copy', str);
        fprintf('Copied to clipboard: %s\n', str);
    end

    function s = formatLabelCell(lbls)
        if isempty(lbls), s = '{}'; return; end
        lbls = cellfun(@(t) char(string(t)), lbls, 'UniformOutput', false);
        lbls = cellfun(@(t) strrep(t, '''', ''''''), lbls, 'UniformOutput', false);
        s = ['{''' strjoin(lbls, ''',''') '''}'];
    end
end