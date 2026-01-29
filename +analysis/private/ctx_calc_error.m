function err = ctx_calc_error(type, stack, idxs)
    if isempty(stack), err = []; return; end
    n = size(stack, 3);
    data = squeeze(mean(stack(idxs,:,:), 1)); % Avg over channels first
    if size(stack,1) == 1 && numel(idxs) == 1, data = squeeze(stack(idxs,:,:)); end % Handle single channel case logic if needed
    
    % If data became a vector (1 timepoint), fix dimensions
    if isvector(data) && n > 1, data = reshape(data, [], n); end

    if strcmp(type, 'se')
        err = std(data, 0, 2)' / sqrt(n);
    else
        err = std(data, 0, 2)';
    end
end