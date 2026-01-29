function labels = idx2chans(EEG, idx, varargin)
% IDX2CHANS  Map channel indices to labels (preserves input order).
%
% Usage:
%   lbl = idx2chans(EEG, [1 2 10]);
%   lbl = idx2chans(EEG, mask);            % logical mask ok
%
% Name-Value:
%   'Source'       - 'urchanlocs' | 'chanlocs'   (default 'urchanlocs')
%   'OnMissing'    - 'empty' | 'index' | 'nan'   (default 'empty')
%   'AsString'     - true/false (return string array vs cellstr) (default false)
%   'Unique'       - true/false (unique w/ stable order)         (default false)
%
% Returns:
%   labels         - cellstr (or string array if AsString=true)

    % ---- Parse inputs ----
    p = inputParser;
    p.addRequired('EEG', @isstruct);
    p.addRequired('idx', @(x) isnumeric(x) || islogical(x));
    p.addParameter('Source','urchanlocs', @(s) any(strcmpi(s,{'urchanlocs','chanlocs'})));
    p.addParameter('OnMissing','empty', @(s) any(strcmpi(s,{'empty','index','nan'})));
    p.addParameter('AsString', false, @(x)islogical(x)&&isscalar(x));
    p.addParameter('Unique',   false, @(x)islogical(x)&&isscalar(x));
    p.parse(EEG, idx, varargin{:});
    R = p.Results;

    % Normalize idx -> numeric row vector
    if islogical(idx), idx = find(idx); end
    idx = idx(:).';   % row

    % Choose source of labels
    switch lower(R.Source)
        case 'urchanlocs'
            if isfield(EEG,'urchanlocs') && ~isempty(EEG.urchanlocs)
                locs = EEG.urchanlocs;
            else
                warning('idx2chans:urchanlocsMissing', ...
                        'EEG.urchanlocs not found. Falling back to chanlocs.');
                locs = EEG.chanlocs;
            end
        case 'chanlocs'
            locs = EEG.chanlocs;
    end

    nLoc = numel(locs);
    labels = repmat({''}, 1, numel(idx));

    if isempty(idx) || nLoc==0
        labels = finalizeType(labels, R.AsString);
        return;
    end

    % Prepare label map from chosen locs
    baseLabels = repmat({''}, 1, nLoc);
    hasLab = false(1, nLoc);
    for k = 1:nLoc
        if isfield(locs(k),'labels') && ~isempty(locs(k).labels)
            baseLabels{k} = locs(k).labels;
            hasLab(k) = true;
        end
    end

    % Fill outputs
    for ii = 1:numel(idx)
        k = idx(ii);
        if k >= 1 && k <= nLoc && hasLab(k)
            labels{ii} = baseLabels{k};
        else
            labels{ii} = missingLabel(k, R.OnMissing);
        end
    end

    % Unique (stable) if requested
    if R.Unique
        [~, ia] = unique(idx, 'stable');
        labels = labels(ia);
    end

    % Convert type if requested
    labels = finalizeType(labels, R.AsString);
end

% ---- helpers ----
function s = missingLabel(k, mode)
    switch lower(mode)
        case 'index', s = sprintf('#%d', k);
        case 'nan',   s = 'NaN';
        otherwise,    s = '';
    end
end

function out = finalizeType(cellLabels, asString)
    if asString
        out = string(cellLabels);
    else
        out = cellLabels;
    end
end
