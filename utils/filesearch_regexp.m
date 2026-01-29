function [paths, names] = filesearch_regexp(startDir, expression, recurse)
% filesearch_regexp searches for files/folders whose *names* match a regex.
%
% Usage:
%   [paths, names] = filesearch_regexp(startDir, expression, [recurse])
%
% Inputs:
%   startDir   - Starting directory
%   expression - Regex applied to item names (case-insensitive)
%   recurse    - 1 (default) to search subfolders, 0 to stay in startDir
%
% Outputs:
%   paths - Parent paths of matching items
%   names - Names of matching items
%
% Notes:
% - Works for EGI .mff “files” (which are folders). Example pattern:
%   'sub-.*?task-mid_run-1_eeg\.mff$'

if nargin < 3 || isempty(recurse), recurse = 1; end
recurse = logical(recurse);

if ~exist(startDir, 'dir')
    error('Starting directory does not exist: %s', startDir);
end

[paths, names] = dir_search(startDir);

    function [paths, names] = dir_search(currDir)
        paths = {};
        names = {};

        listing = dir(currDir);
        listing = listing(~ismember({listing.name}, {'.','..'})); % skip dots

        for k = 1:numel(listing)
            itemName = listing(k).name;
            itemPath = fullfile(currDir, itemName);

            % Record match if name matches regex (return parent dir)
            if ~isempty(regexpi(itemName, expression))
                paths{end+1} = currDir; %#ok<AGROW>
                names{end+1} = itemName; %#ok<AGROW>
            end

            % Recurse if requested
            if recurse && listing(k).isdir
                [subPaths, subNames] = dir_search(itemPath);
                if ~isempty(subPaths)
                    paths = [paths, subPaths]; %#ok<AGROW>
                    names = [names, subNames]; %#ok<AGROW>
                end
            end
        end
    end
end
