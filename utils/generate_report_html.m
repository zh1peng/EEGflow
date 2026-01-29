function generate_report_html(folderPath)
% GENERATE_REPORT_HTML  Generates an HTML report from EEG preprocessing logs.
%   This function scans a specified folder for log files (.txt) and plot
%   images (.png) generated during EEG data preprocessing. It then compiles
%   them into a single HTML file for easy review.
%
%   The function identifies PNG files based on common naming patterns from the
%   EEGdojo toolbox and groups them under relevant headings. It also embeds the
%   content of any .txt log file found in the folder.
%
% Syntax:
%   generate_report_html(folderPath)
%
% Input Arguments:
%   folderPath  - (char | string) The path to the folder containing the log
%                 files and images.
%
% Example:
%   % Assuming your logs are in 'C:\EEG_Study\Subject01\logs'
%   generate_report_html('C:\EEG_Study\Subject01\logs');
%   % This will create a 'Preprocessing_Report.html' file in that folder.
%
% See also: natsort

    % --- Input Validation ---
    if ~exist('natsort', 'file')
        error('natsort function is required. Please add it to your MATLAB path. It can be downloaded from the MATLAB File Exchange.');
    end
    if ~exist(folderPath, 'dir')
        error('The specified folder does not exist: %s', folderPath);
    end

    % --- File Patterns for PNG Images ---
    % The function will also find other PNGs and group them by filename prefix.
    patterns = {
        'BadChannel', 'Bad Channel Detection';
        'Kurt', 'Bad Channels - Kurtosis';
        'Spec', 'Bad Channels - Spectrum';
        'Prob', 'Bad Channels - Probability';
        'MeanCorr', 'Bad Channels - FASTER Mean Correlation';
        'Variance', 'Bad Channels - FASTER Variance';
        'Hurst', 'Bad Channels - FASTER Hurst';
        'Flatline', 'Bad Channels - CleanRaw Flatline';
        'CleanChan', 'Bad Channels - CleanRaw Noise';
        'ICA_reject', 'ICA Component Rejection';
        'BadICs_FASTER', 'Bad ICs - FASTER';
        'BadICs_IClabel', 'Bad ICs - ICLabel';
    };

    % --- Initialize HTML Content ---
    htmlContent = ['<html><head><title>EEG Preprocessing Report</title><style>' ...
                   'body { font-family: Arial, sans-serif; margin: 40px; background-color: #f4f4f9; color: #333; }' ...
                   'h1 { color: #005a9c; text-align: center; }' ...
                   'h2 { color: #005a9c; border-bottom: 2px solid #005a9c; padding-bottom: 10px; margin-top: 40px; }' ...
                   '.container { margin-bottom: 40px; background-color: #fff; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }' ...
                   '.image-gallery { display: flex; flex-wrap: wrap; gap: 15px; }' ...
                   '.image-container { flex: 1 1 calc(33.333% - 15px); box-sizing: border-box; text-align: center; }' ...
                   'img { max-width: 100%; height: auto; border-radius: 4px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); cursor: pointer; transition: transform 0.2s; }' ...
                   'img:hover { transform: scale(1.05); }' ...
                   '.log-content { white-space: pre-wrap; background-color: #2b2b2b; color: #f0f0f0; padding: 15px; border-radius: 5px; font-family: monospace; }' ...
                   '</style></head><body><h1>EEG Preprocessing Report</h1>'];

    % --- Process Log Files (.txt) ---
    logFiles = dir(fullfile(folderPath, '*.txt'));
    if ~isempty(logFiles)
        htmlContent = [htmlContent, '<div class="container"><h2>Log File Content</h2>'];
        for i = 1:length(logFiles)
            logFilePath = fullfile(folderPath, logFiles(i).name);
            fileContent = fileread(logFilePath);
            htmlContent = [htmlContent, sprintf('<h3>%s</h3><div class="log-content">%s</div>', logFiles(i).name, fileContent)];
        end
        htmlContent = [htmlContent, '</div>'];
    end

    % --- Process Image Files (.png) ---
    allPngFiles = dir(fullfile(folderPath, '*.png'));
    if isempty(allPngFiles)
        htmlContent = [htmlContent, '<div class="container"><h2>No Images Found</h2><p>No PNG images were found in the specified directory.</p></div>'];
    else
        fileNames = {allPngFiles.name};
        
        % Group files by prefix (e.g., 'BadChannel_Kurt_S01' -> 'BadChannel_Kurt')
        prefixes = regexp(fileNames, '^([a-zA-Z_]+)', 'tokens', 'once');
        prefixes = [prefixes{:}];
        uniquePrefixes = unique(prefixes);

        for i = 1:length(uniquePrefixes)
            prefix = uniquePrefixes{i};
            heading = strrep(prefix, '_', ' '); % Default heading
            
            % Check if a more descriptive heading is available in patterns
            matchIdx = find(strcmpi(patterns(:,1), prefix));
            if ~isempty(matchIdx)
                heading = patterns{matchIdx, 2};
            end

            htmlContent = [htmlContent, sprintf('<div class="container"><h2>%s</h2><div class="image-gallery">', heading)];
            
            % Get all files for the current prefix and sort them
            groupFiles = fileNames(strcmp(prefixes, prefix));
            sortedGroupFiles = natsort(groupFiles);

            for j = 1:length(sortedGroupFiles)
                fileName = sortedGroupFiles{j};
                htmlContent = [htmlContent, ...
                    sprintf('<div class="image-container"><a href="%s" target="_blank"><img src="%s" alt="%s"></a><p>%s</p></div>', ...
                    fileName, fileName, fileName, strrep(fileName, '_', ' ' ))];
            end
            htmlContent = [htmlContent, '</div></div>'];
        end
    end

    % --- Finalize and Write HTML File ---
    htmlContent = [htmlContent, '</body></html>'];
    htmlFilePath = fullfile(folderPath, 'Preprocessing_Report.html');
    try
        fileId = fopen(htmlFilePath, 'w');
        fprintf(fileId, '%s', htmlContent);
        fclose(fileId);
        fprintf('Successfully generated HTML report: <a href="file:///%s">%s</a>\n', htmlFilePath, htmlFilePath);
    catch ME
        error('Failed to write HTML file: %s\n%s', htmlFilePath, ME.message);
    end
end