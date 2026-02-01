function batch_saveas(figHandle, saveName, scaleFactor)
   % batch_saveas - Save a figure as an image file with optional scaling.
    %
    % Description:
    %   This function saves a figure to a specified file, optionally scaling its size 
    %   for higher resolution. It uses `getframe` and `imwrite` for broad compatibility 
    %   across MATLAB versions and systems. This method avoids platform-specific issues 
    %   with `print` or `exportgraphics`.
    %
    % Inputs:
    %   figHandle   - Handle to the figure to save (must be a valid figure handle).
    %   saveName    - Full file path and name to save the figure (e.g., 'output.png').
    %   scaleFactor - Optional scaling factor for figure size (default = 1.2).
    %
    % Outputs:
    %   None. The figure is saved to the specified file path.
    %
    % Notes:
    %   - The function scales the figure size temporarily for saving.
    %   - The figure is closed after saving to avoid clutter.
    %   - `imwrite` is used for broad platform compatibility.
    %
    % Example:
    %   figHandle = figure;
    %   plot(rand(1, 10));
    %   batch_saveas(figHandle, 'example_figure.png', 1.5);
    %
    % Author: Zhipeng Cao, 2024 (zhipeng30@foxmail.com)
    % Updated: 2024


    % --------------------- Input Validation ---------------------
    if ~ishghandle(figHandle, 'figure')
        error('batch_saveas:InvalidHandle', 'Invalid figure handle provided.');
    end
    
    if nargin < 3 || isempty(scaleFactor)
        scaleFactor = 1.2; % Default scaling factor
    end
    
    if ~ischar(saveName) && ~isstring(saveName)
        error('batch_saveas:InvalidSaveName', 'saveName must be a valid string or character array.');
    end

    % --------------------- Resize the Figure ---------------------
    try
        % Get the current figure position (left, bottom, width, height)
        currentPosition = get(figHandle, 'Position');

        % Calculate new figure position with scaling
        newPosition = currentPosition .* [1 1 scaleFactor scaleFactor];

        % Apply the new size to the figure
        set(figHandle, 'Position', newPosition);
    catch
        warning('Failed to resize the figure. Using original size.');
    end

    % --------------------- Capture and Save the Figure ---------------------
    try
        % Capture the figure content
        frame = getframe(figHandle); % Works for most systems and figure types
        img = frame2im(frame);       % Convert frame to image matrix

        % Save the image using imwrite
        imwrite(img, saveName);

        % Log success
        fprintf('Figure successfully saved to: %s\n', saveName);
    catch ME
        error('batch_saveas:SaveFailed', 'Failed to save the figure: %s', ME.message);
    end

    % --------------------- Cleanup ---------------------
    try
        % Close the figure to avoid clutter
        close(figHandle);
    catch
        warning('Failed to close the figure. You may close it manually.');
    end
end
    % Save the figure using print 
    % print(figHandle, saveName, '-dpng', '-r300'); % '-r300' sets the
    % resolution to 300 dpi  Error message: Printing of uicontrols is not supported on this platform.
    
     % Save the figure using exportgraphics (requires MATLAB R2020a or newer)
    % exportgraphics(figHandle, saveName, 'Resolution', 300); % no label!
    % Optionally, you might want to reset the figure to its original size here
    % set(figHandle, 'Position', currentPosition);
    
    % Close the figure




