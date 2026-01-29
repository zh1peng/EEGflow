function state = erp_define_roi(state, args, ~)
%ERP_DEFINE_ROI Define an ROI for ERP analysis.
% Args: name (char), labels (cellstr)

    state_check(state);
    name = args.name;
    labels = args.labels;

    [valid, missing] = state_validate_chans(state, labels);
    if ~isempty(missing)
        warning('ROI "%s": missing channels ignored: %s', name, strjoin(missing, ', '));
    end
    if isempty(valid)
        error('ROI "%s" has no valid channels.', name);
    end
    state.Selection.ROIs.(name) = valid;
    fprintf('ROI "%s" defined (%d channels).\n', name, numel(valid));
end
