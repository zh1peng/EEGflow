function state_require_eeg(state, opName)
%STATE_REQUIRE_EEG Ensure state.EEG exists before running an op.
    if nargin < 2, opName = 'operation'; end
    if nargin < 1 || ~isstruct(state) || ~isfield(state, 'EEG') || isempty(state.EEG)
        error('PrepState:NoEEG', 'EEG is empty. Load data before running %s.', opName);
    end
end
