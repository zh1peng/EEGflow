function [state, features_table] = erp_extract_feature(state, args, ~)
%ERP_EXTRACT_FEATURE Extract ERP features for ROI/time window.
% Args: roi, time_window, feature_func, peak_polarity

    if nargin < 2, args = struct(); end
    if ~isfield(args, 'roi'), args.roi = ''; end
    if ~isfield(args, 'time_window'), args.time_window = ''; end
    if ~isfield(args, 'feature_func'), args.feature_func = 'mean'; end
    if ~isfield(args, 'peak_polarity'), args.peak_polarity = 'max'; end

    state_check(state, 'ERPs');
    if isempty(args.roi) || ~isfield(state.Selection.ROIs, args.roi)
        error('Specify a valid ROI.');
    end
    if isempty(args.time_window) || ~isfield(state.Selection.TimeWindows, args.time_window)
        error('Specify a valid time window.');
    end

    fprintf('Extracting features for ROI "%s" in window "%s"...\n', args.roi, args.time_window);
    [chan_indices, ~] = state_get_indices(state, args.roi);
    time_range = state.Selection.TimeWindows.(args.time_window);
    time_indices = state.Dataset.times >= time_range(1) & state.Dataset.times <= time_range(2);
    times_in_window = state.Dataset.times(time_indices);

    results_list = {};
    group_names = fieldnames(state.Selection.Groups);
    for g = 1:numel(group_names)
        group_name = group_names{g};
        subject_ids = state.Selection.Groups.(group_name);
        for s = 1:numel(subject_ids)
            subject_id = subject_ids{s};
            sub_field = state_subject_field(state, subject_id);
            for c = 1:numel(state.Selection.Conditions)
                condition_name = state.Selection.Conditions{c};
                if isfield(state.Results.ERPs, sub_field) && isfield(state.Results.ERPs.(sub_field), condition_name)
                    subject_erp = state.Results.ERPs.(sub_field).(condition_name);
                    roi_erp = mean(subject_erp(chan_indices, time_indices), 1);
                    feature_values = compute_feature(args.feature_func, roi_erp, times_in_window, args.peak_polarity);
                    results_list(end+1, :) = {subject_id, group_name, condition_name, feature_values}; %#ok<AGROW>
                end
            end
        end
    end

    if isempty(results_list)
        warning('No data found to extract features.');
        features_table = table();
        return;
    end

    base_vars = {'SubjectID', 'Group', 'Condition'};
    if ischar(args.feature_func) && strcmpi(args.feature_func, 'peak')
        feature_names = {[args.roi '_' args.time_window '_peak_amp'], [args.roi '_' args.time_window '_peak_lat']};
        temp_results = [results_list{:,4}];
        flat_results = [results_list(:,1:3), num2cell(reshape(temp_results, [], 2))];
    else
        if ischar(args.feature_func)
            feature_name_str = args.feature_func;
        else
            feature_name_str = func2str(args.feature_func);
        end
        feature_names = {[args.roi '_' args.time_window '_' feature_name_str]};
        flat_results = [results_list(:,1:3), num2cell([results_list{:,4}]')];
    end
    features_table = cell2table(flat_results, 'VariableNames', [base_vars, feature_names]);

    if ischar(args.feature_func)
        feature_field_name = [args.roi '_' args.time_window '_' args.feature_func];
    else
        feature_field_name = [args.roi '_' args.time_window '_' func2str(args.feature_func)];
    end
    state.Results.Features.(feature_field_name) = features_table;
    fprintf('Done. Feature table created with %d rows.\n', height(features_table));
end

function feature_values = compute_feature(feature_func, roi_erp, times_in_window, peak_polarity)
    if isa(feature_func, 'function_handle')
        feature_values = feature_func(roi_erp, times_in_window);
        return;
    end
    switch lower(feature_func)
        case 'mean'
            feature_values = mean(roi_erp);
        case 'median'
            feature_values = median(roi_erp);
        case 'peak'
            if strcmpi(peak_polarity, 'max')
                [val, idx] = max(roi_erp);
            else
                [val, idx] = min(roi_erp);
            end
            feature_values = [val, times_in_window(idx)];
        case 'latency'
            if strcmpi(peak_polarity, 'max')
                [~, idx] = max(roi_erp);
            else
                [~, idx] = min(roi_erp);
            end
            feature_values = times_in_window(idx);
        otherwise
            error('Unknown feature: %s', feature_func);
    end
end
