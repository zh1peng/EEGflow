function params = state_strip_eeg_param(params)
%STATE_STRIP_EEG_PARAM Remove EEG field from params if present.
    if isstruct(params) && isfield(params, 'EEG')
        params = rmfield(params, 'EEG');
    end
end
