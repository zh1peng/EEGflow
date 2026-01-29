function [idxs, title_str] = state_get_indices(state, target)
%STATE_GET_INDICES Resolve ROI/channel indices and title string.
    if isfield(state.Selection, 'ROIs') && isfield(state.Selection.ROIs, target)
        labels = state.Selection.ROIs.(target);
        [valid, missing] = state_validate_chans(state, labels);
        if ~isempty(missing)
            warning('ROI "%s": missing channels ignored: %s', target, strjoin(missing, ', '));
        end
        if isempty(valid)
            error('ROI "%s" has no valid channels.', target);
        end
        idxs = find(ismember({state.Dataset.chanlocs.labels}, valid));
        title_str = sprintf('ROI: %s', target);
    else
        [valid, ~] = state_validate_chans(state, {target});
        if isempty(valid)
            error('Channel "%s" not found.', target);
        end
        idxs = find(strcmp({state.Dataset.chanlocs.labels}, valid{1}));
        title_str = sprintf('Channel: %s', target);
    end

    if isempty(idxs)
        error('No valid channels found for "%s".', target);
    end
end
