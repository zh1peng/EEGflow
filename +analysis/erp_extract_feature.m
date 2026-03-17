function [state, features_table] = erp_extract_feature(state, args, ~)
%ERP_EXTRACT_FEATURE Extract ERP features for ROI/time window.
% Args: roi, time_window, feature_func, peak_polarity

    if nargin < 2, args = struct(); end
    if ~isfield(args, 'roi'), args.roi = ''; end
    if ~isfield(args, 'time_window'), args.time_window = ''; end
    if ~isfield(args, 'feature_func'), args.feature_func = 'mean'; end
    if ~isfield(args, 'peak_polarity'), args.peak_polarity = 'max'; end
    if isstring(args.roi), args.roi = char(args.roi); end
    if isstring(args.time_window), args.time_window = char(args.time_window); end
    if isstring(args.feature_func), args.feature_func = char(args.feature_func); end
    if isstring(args.peak_polarity), args.peak_polarity = char(args.peak_polarity); end

    state_check(state, 'ERPs');
    if isempty(args.roi) || ~isfield(state.Selection.ROIs, args.roi)
        error('Specify a valid ROI.');
    end
    if isempty(args.time_window) || ~isfield(state.Selection.TimeWindows, args.time_window)
        error('Specify a valid time window.');
    end

    ver = analysis.get_version();
    fprintf('Extracting features for ROI "%s" in window "%s"... [EEGflow v%s]\n', ...
        args.roi, args.time_window, ver);
    [chan_indices, ~] = state_get_indices(state, args.roi);
    time_range = state.Selection.TimeWindows.(args.time_window);
    time_indices = state.Dataset.times >= time_range(1) & state.Dataset.times <= time_range(2);
    if ~any(time_indices)
        error('Time window "%s" does not overlap dataset time range.', args.time_window);
    end
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
                    feature_values = reshape(feature_values, 1, []);
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
    feature_len = numel(results_list{1,4});
    feature_mat = nan(size(results_list, 1), feature_len);
    for i = 1:size(results_list, 1)
        v = results_list{i,4};
        if numel(v) ~= feature_len
            error('Feature output size mismatch across rows. Keep feature length consistent.');
        end
        feature_mat(i, :) = reshape(v, 1, []);
    end
    feature_names = build_feature_names(args, feature_len);
    flat_results = [results_list(:,1:3), num2cell(feature_mat)];
    features_table = cell2table(flat_results, 'VariableNames', [base_vars, feature_names]);

    feature_field_name = make_field_key(sprintf('%s_%s_%s', ...
        args.roi, args.time_window, feature_func_key(args.feature_func)));
    state.Results.Features.(feature_field_name) = features_table;
    fprintf('Done. Feature table created with %d rows.\n', height(features_table));
end

function feature_values = compute_feature(feature_func, roi_erp, times_in_window, peak_polarity)
    if isa(feature_func, 'function_handle')
        feature_values = feature_func(roi_erp, times_in_window);
        if ~isnumeric(feature_values) || isempty(feature_values)
            error('Custom feature function must return numeric output.');
        end
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

function feature_names = build_feature_names(args, feature_len)
    roi_key = make_field_key(args.roi);
    tw_key = make_field_key(args.time_window);
    if ischar(args.feature_func) && strcmpi(args.feature_func, 'peak') && feature_len == 2
        feature_names = {sprintf('%s_%s_peak_amp', roi_key, tw_key), ...
            sprintf('%s_%s_peak_lat', roi_key, tw_key)};
        return;
    end

    base_key = make_field_key(feature_func_key(args.feature_func));
    if feature_len == 1
        feature_names = {sprintf('%s_%s_%s', roi_key, tw_key, base_key)};
        return;
    end

    feature_names = cell(1, feature_len);
    for k = 1:feature_len
        feature_names{k} = sprintf('%s_%s_%s_%d', roi_key, tw_key, base_key, k);
    end
end

function key = feature_func_key(feature_func)
    if ischar(feature_func)
        key = feature_func;
    else
        key = func2str(feature_func);
    end
end

function key = make_field_key(txt)
    key = lower(regexprep(char(txt), '[^A-Za-z0-9]', '_'));
    if ~isempty(key) && isstrprop(key(1), 'digit')
        key = ['x' key];
    end
end
