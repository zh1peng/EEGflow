function [idxs, title_str] = ctx_get_indices(ctx, target)
    if isfield(ctx.Selection.ROIs, target)
        labels = ctx.Selection.ROIs.(target);
        idxs = find(ismember({ctx.Dataset.chanlocs.labels}, labels));
        title_str = sprintf('ROI: %s', target);
    else
        idxs = find(strcmp({ctx.Dataset.chanlocs.labels}, target));
        title_str = sprintf('Channel: %s', target);
    end
    if isempty(idxs), error('Target "%s" not found in ROIs or Channels.', target); end
end