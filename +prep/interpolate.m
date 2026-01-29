function [EEG, out] = interpolate(EEG, varargin)
% INTERPOLATE Interpolates missing channels in EEG data.
%   This function identifies channels present in the original channel locations
%   (`EEG.urchanlocs`) but missing from the current EEG dataset (`EEG.chanlocs`),
%   and then interpolates their data using spherical interpolation. This is
%   typically used to restore data for channels that were removed (e.g., bad channels).
%
% Syntax:
%   [EEG, out] = prep.interpolate(EEG, 'param', value, ...)
%
% Input Arguments:
%   EEG         - EEGLAB EEG structure. Must contain `EEG.urchanlocs` with
%                 original channel locations.
%
% Optional Parameters (Name-Value Pairs):
%   'LogFile'   - (char | string, default: '')
%                 Path to a log file for verbose output. If empty, output
%                 is directed to the command window.
%
% Output Arguments:
%   EEG         - Modified EEGLAB EEG structure with interpolated channels.
%   out         - Structure containing output information:
%                 out.interpolated_channels - (cell array of strings) Labels
%                                             of channels that were interpolated.
%
% Examples:
%   % Example 1: Interpolate missing channels (without pipeline)
%   % Assume EEG has some channels removed and EEG.urchanlocs is set.
%   % e.g., EEG = pop_select(EEG, 'nochannel', [1 5]);
%   % EEG.urchanlocs = original_EEG.chanlocs;
%   EEG_interpolated = prep.interpolate(EEG);
%   disp('Missing channels interpolated.');
%
%   % Example 2: Usage within a pipeline
%   % Assuming 'pipe' is an initialized pipeline object
%   pipe = pipe.addStep(@prep.interpolate, ...
%       'LogFile', p.LogFile); %% p.LogFile from pipeline parameters
%   % Then run the pipeline: [EEG_processed, results] = pipe.run(EEG);
%   disp('Missing channels interpolated via pipeline.');
%
% See also: pop_interp, eeg_checkset

    % ----------------- Parse inputs -----------------
    p = inputParser;
    p.addRequired('EEG', @isstruct);
    p.addParameter('LogFile', '', @ischar);

    p.parse(EEG, varargin{:});
    R = p.Results;

    out = struct(); % Initialize output structure
    out.interpolated_channels = {};


    logPrint(R.LogFile, '[interpolate] Starting channel interpolation.');

    if ~isfield(EEG, 'urchanlocs') || isempty(EEG.urchanlocs)
        error('[interpolate] Skipping interpolation: No original channel locations (EEG.urchanlocs) found. Ensure EEG.urchanlocs is set before calling this function.');
    end

    original_chans = {EEG.urchanlocs.labels};
    current_chans = {EEG.chanlocs.labels};
    chans_to_interp = setdiff(original_chans, current_chans);

    if isempty(chans_to_interp)
        logPrint(R.LogFile, '[interpolate] Skipping interpolation: No channels to interpolate found.');
        return;
    end

    logPrint(R.LogFile, sprintf('[interpolate] Interpolating %d channels: %s', numel(chans_to_interp), strjoin(chans_to_interp, ', ')));
    EEG = pop_interp(EEG, EEG.urchanlocs, 'spherical');
    EEG = eeg_checkset(EEG); % Update EEG structure after changes
    logPrint(R.LogFile, '[interpolate] Interpolation complete.');
    out.interpolated_channels = chans_to_interp;

end