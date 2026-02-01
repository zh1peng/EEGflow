function state = load_mff(state, args, meta)
%LOAD_MFF Load an EGI .mff dataset into the flow state.
%
% Purpose & behavior
%   Uses EEGLAB's pop_mffimport to load EGI .mff data, checks the dataset
%   with eeg_checkset, and stores it in state.EEG.
%
% Flow/state contract
%   Required input state fields:
%     - none (state may be empty)
%   Updated/created state fields:
%     - state.EEG (loaded EEGLAB dataset)
%     - state.history (appends a run record)
%
% Inputs
%   state (struct)
%     - Flow state; see Flow/state contract above.
%   args (struct)
%     - Parameters for this operation (listed below). Merged with state.cfg.load_mff if present.
%   meta (struct, optional)
%     - Pipeline meta; supports validate_only/logger.
%
% Parameters
%   - filename
%       Type: char; Default: ''
%       Name of the .mff folder/file (e.g., 'sub01.mff').
%   - filepath
%       Type: char; Default: ''
%       Parent folder containing the .mff.
%   - LogFile
%       Type: char; Default: ''
%       If non-empty, logs are appended to this file and also sent to the pipeline logger.
% Outputs
%   state (struct)
%     - Updated flow state (see Flow/state contract above).
%
% Side effects
%   state
%     state.EEG is replaced with the loaded dataset.
%   Files
%     Reads the .mff bundle from disk.
%
% Usage
%   state = prep.load_mff(state, struct('filename','sub01.mff','filepath','./data'));
%
% See also: pop_mffimport, eeg_checkset, prep.load_set

    if nargin < 1 || isempty(state), state = struct(); end
    if nargin < 2 || isempty(args), args = struct(); end
    if nargin < 3 || isempty(meta), meta = struct(); end

    op = 'load_mff';
    cfg = state_get_config(state, op);
    params = state_merge(cfg, args);

    p = inputParser;
    p.addParameter('filename','',@ischar);
    p.addParameter('filepath','',@ischar);
    p.addParameter('LogFile', '', @ischar);
    nv = state_struct2nv(params);
    p.parse(nv{:});
    R = p.Results;

    if isfield(meta, 'validate_only') && meta.validate_only
        state = state_update_history(state, op, R, 'validated', struct());
        return;
    end

    fullPath = fullfile(R.filepath, R.filename);
    state = log_step(state, meta, R.LogFile, sprintf('[load_mff] Loading MFF dataset: %s', fullPath));

    EEG = pop_mffimport({fullPath}, {'code'}, 0, 0);
    EEG = eeg_checkset(EEG);
    state.EEG = EEG;
    out = struct('loadedFile', fullPath);

    state = log_step(state, meta, R.LogFile, sprintf('[load_mff] Dataset loaded successfully: %s', fullPath));
    state = state_update_history(state, op, R, 'success', out);
end
