function pow = compute_source_power(sourceData, varargin)
%COMPUTE_SOURCE_POWER Mean-square power from source/parcel time series.
%
% Usage:
%   pow = source.compute_source_power(src)
%   pow = source.compute_source_power(data, spatialFilter, params)

    if nargin >= 2 && isstruct(varargin{1}) && isfield(varargin{1}, 'inside')
        data = sourceData;
        spatialFilter = varargin{1};
        if numel(varargin) >= 2 && isstruct(varargin{2})
            params = varargin{2};
        else
            params = struct();
        end
        [virt, src] = source.reconstruct_virtual_channels(data, spatialFilter, params);
        sourceData = src;
        sourceData.label = virt.label(:);
    end

    if ~isstruct(sourceData) || ~isfield(sourceData, 'trial')
        error('source:compute_source_power:BadInput', ...
            'Input must be a source struct with trial cells, or data + spatialFilter.');
    end

    nTr = numel(sourceData.trial);
    if nTr < 1
        error('source:compute_source_power:NoTrials', 'No source trials found.');
    end
    nSig = size(sourceData.trial{1}, 1);
    pow = zeros(nSig, 1);
    for t = 1:nTr
        X = double(sourceData.trial{t});
        if size(X, 1) ~= nSig
            error('source:compute_source_power:BadTrials', ...
                'Inconsistent signal count across source trials.');
        end
        pow = pow + mean(X.^2, 2, 'omitnan');
    end
    pow = pow / nTr;
end
