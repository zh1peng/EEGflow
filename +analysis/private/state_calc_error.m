function err = state_calc_error(type, stack, idxs)
%STATE_CALC_ERROR Compute error band for ERP stack.
    if isempty(stack)
        err = [];
        return;
    end
    n = size(stack, 3);
    data = squeeze(mean(stack(idxs, :, :), 1));
    if size(stack, 1) == 1 && numel(idxs) == 1
        data = squeeze(stack(idxs, :, :));
    end
    if isvector(data) && n > 1
        data = reshape(data, [], n);
    end

    switch lower(type)
        case 'se'
            err = std(data, 0, 2)' / sqrt(n);
        case 'std'
            err = std(data, 0, 2)';
        otherwise
            err = [];
    end
end
