function state_check(state, req_field)
%STATE_CHECK Validate analysis state and required results.
    if nargin < 2, req_field = ''; end
    if ~isfield(state, 'Dataset') || ~isa(state.Dataset, 'analysis.Dataset')
        error('analysis_state:InvalidState', 'State must contain a valid analysis.Dataset.');
    end
    if ~isfield(state, 'Results')
        error('analysis_state:InvalidState', 'State must contain a Results struct. Use analysis.init_state.');
    end
    if ~isempty(req_field)
        switch req_field
            case 'ERPs'
                if ~isfield(state.Results, 'ERPs') || isempty(fieldnames(state.Results.ERPs))
                    error('analysis_state:MissingResult', 'Subject ERPs not found. Run erp_compute_erps first.');
                end
            case 'GA'
                if ~isfield(state.Results, 'GA') || isempty(fieldnames(state.Results.GA))
                    error('analysis_state:MissingResult', 'Grand Averages not found. Run erp_compute_ga first.');
                end
            case 'GA_TFD'
                if ~isfield(state.Results, 'GA_TFD') || isempty(fieldnames(state.Results.GA_TFD))
                    error('analysis_state:MissingResult', 'TF Grand Averages not found. Run tf_compute_ga first.');
                end
            case 'Contrasts'
                if ~isfield(state.Results, 'Contrasts') || isempty(fieldnames(state.Results.Contrasts))
                    error('analysis_state:MissingResult', 'Contrasts not found. Define contrasts first.');
                end
        end
    end
end
