function state = load_set(state, args, meta)
%LOAD_SET Load an EEGLAB .set dataset into the flow state.
%
% Purpose & behavior
%   Loads a .set dataset from disk using EEGLAB's pop_loadset, validates it
%   with eeg_checkset, and stores it in state.EEG. This is typically the
%   first step in a prep pipeline.
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
%     - Parameters for this operation (listed below). Merged with state.cfg.load_set if present.
%   meta (struct, optional)
%     - Pipeline meta; supports validate_only/logger.
%
% Parameters
%   - filename
%       Type: char; Default: ''
%       Name of the .set file, e.g., 'sub01.set'.
%   - filepath
%       Type: char; Default: ''
%       Folder containing the file.
%   - LogFile
%       Type: char; Default: ''
%       If non-empty, logPrint writes progress to this file; otherwise to console.
% Example args
%   args = struct('filename','sub-101_task-mid_run-01_eeg.set','filepath','/data');
%
% Outputs
%   state (struct)
%     - Updated flow state (see Flow/state contract above).
%
% Side effects
%   state
%     state.EEG is replaced with the loaded dataset.
%   Files
%     Reads the .set (and associated .fdt if present) from disk.
%
% Usage
%   state = prep.load_set(state, struct('filename','sub01.set','filepath','./data'));
%   state = prep.load_set(state, struct('filename','sub01.set','filepath','./data','LogFile','prep.log'));
%
% See also: pop_loadset, eeg_checkset, prep.load_mff, prep.save_set

    if nargin < 1 || isempty(state), state = struct(); end
    if nargin < 2 || isempty(args), args = struct(); end
    if nargin < 3 || isempty(meta), meta = struct(); end

    op = 'load_set';
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

    state_log(meta, sprintf('[load_set] Loading dataset: %s/%s', R.filepath, R.filename));
    EEG = pop_loadset('filename', R.filename, 'filepath', R.filepath);
    EEG = eeg_checkset(EEG);
    state.EEG = EEG;
    out = struct('loadedFile', fullfile(R.filepath, R.filename));
    state_log(meta, sprintf('[load_set] Dataset loaded %s/%s', R.filepath, R.filename));

    state = state_update_history(state, op, R, 'success', out);
end
