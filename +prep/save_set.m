function state = save_set(state, args, meta)
%SAVE_SET Save state.EEG to disk as an EEGLAB .set.
%
% Purpose & behavior
%   Writes the current dataset to disk using EEGLAB's pop_saveset. Useful
%   at checkpoints in a pipeline.
%
% Flow/state contract
%   Required input state fields:
%     - state.EEG (valid EEGLAB dataset)
%   Updated/created state fields:
%     - state.history (appends a run record)
%
% Inputs
%   state (struct)
%     - Flow state; see Flow/state contract above.
%   args (struct)
%     - Parameters for this operation (listed below). Merged with state.cfg.save_set if present.
%   meta (struct, optional)
%     - Pipeline meta; supports validate_only/logger.
%
% Parameters
%   - filename
%       Type: char; Default: ''
%       Output .set file name (e.g., 'sub01_clean.set').
%   - filepath
%       Type: char; Default: ''
%       Output folder.
%   - LogFile
%       Type: char; Default: ''
%       If non-empty, logPrint writes progress to this file; otherwise to console.
% Outputs
%   state (struct)
%     - Updated flow state (see Flow/state contract above).
%
% Side effects
%   state
%     state.EEG unchanged; history updated.
%   Files
%     Writes .set (and .fdt if applicable) to disk.
%
% Usage
%   state = prep.save_set(state, struct('filename','sub01_clean.set','filepath','./out'));
%
% See also: pop_saveset, prep.load_set

    if nargin < 1 || isempty(state), state = struct(); end
    if nargin < 2 || isempty(args), args = struct(); end
    if nargin < 3 || isempty(meta), meta = struct(); end

    op = 'save_set';
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

    state_require_eeg(state, op);
    state_log(meta, sprintf('[save_set] Saving dataset: %s/%s', R.filepath, R.filename));
    pop_saveset(state.EEG, 'filename', R.filename, 'filepath', R.filepath);
    out = struct('savedFile', fullfile(R.filepath, R.filename));
    state_log(meta, sprintf('[save_set] Dataset saved: %s/%s', R.filepath, R.filename));

    state = state_update_history(state, op, R, 'success', out);
end
