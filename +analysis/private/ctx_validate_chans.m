function [valid, missing] = ctx_validate_chans(ctx, labels)
    ds_chans = {ctx.Dataset.chanlocs.labels};
    is_mem = ismember(labels, ds_chans);
    valid = labels(is_mem);
    missing = labels(~is_mem);
end