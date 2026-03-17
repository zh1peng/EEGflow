function [valid, missing] = state_validate_chans(state, labels)
%STATE_VALIDATE_CHANS Validate channel labels against Dataset.
    ds_chans = {state.Dataset.chanlocs.labels};
    labels = cellstr(labels);
    labels = labels(:)';

    label_keys = lower(string(labels));
    ds_keys = lower(string(ds_chans));
    [is_mem, idx] = ismember(label_keys, ds_keys);
    valid = ds_chans(idx(is_mem));
    valid = unique(valid, 'stable');
    missing = labels(~is_mem);
end
