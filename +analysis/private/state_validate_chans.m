function [valid, missing] = state_validate_chans(state, labels)
%STATE_VALIDATE_CHANS Validate channel labels against Dataset.
    ds_chans = {state.Dataset.chanlocs.labels};
    is_mem = ismember(labels, ds_chans);
    valid = labels(is_mem);
    missing = labels(~is_mem);
end
