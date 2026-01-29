function [idx, notFound, labelsNorm] = chans2idx(EEG, labList, varargin)
% CHANS2IDX Map channel labels to indices (case-insensitive), preserving input order.
%
% Usage:
%   [idx, notFound] = prep.chans2idx(EEG, {'Fp1','Fp2','HEOG'});
%
% Name-Value:
%   'MustExist'   (logical) error if any label missing [default: false]
%
% Returns:
%   idx        : numeric indices in EEG.chanlocs
%   notFound   : cellstr of labels not found
%   labelsNorm : normalized label list (cellstr)

    p = inputParser;
    p.addParameter('MustExist', false, @(x)islogical(x) && isscalar(x));
    p.parse(varargin{:});
    MustExist = p.Results.MustExist;

    % normalize input list to row cellstr
    if isempty(labList)
        idx = []; notFound = {}; labelsNorm = {};
        return;
    elseif ischar(labList)
        labelsNorm = {labList};
    elseif isstring(labList)
        labelsNorm = cellstr(labList(:)).';
    elseif iscell(labList)
        assert(all(cellfun(@(x)ischar(x) || isstring(x), labList)), ...
            '[chans2idx] labList must contain only strings.'); % Updated function name and added prefix
        labelsNorm = cellfun(@char, labList, 'uni', false);
        labelsNorm = labelsNorm(:).';
    else
        error('[chans2idx] labList must be char/string/cellstr.'); % Updated function name and added prefix
    end

    chanLabels = {EEG.chanlocs.labels};
    idx = [];
    notFound = {};

    for i = 1:numel(labelsNorm)
        hit = find(strcmpi(chanLabels, labelsNorm{i}), 1);
        if isempty(hit)
            notFound{end+1} = labelsNorm{i};
        else
            idx(end+1) = hit;
        end
    end

    idx = unique(idx, 'stable');

    if MustExist && ~isempty(notFound)
        error('[chans2idx] NotFound: Channel label(s) not found: %s', strjoin(notFound, ', ')); % Updated function name and added prefix
    end
end