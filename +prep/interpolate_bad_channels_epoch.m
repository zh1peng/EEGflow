function [EEG, out] = interpolate_bad_channels_epoch(EEG, varargin)
% INTERPOLATE_BAD_CHANNELS_EPOCH  Identifies and interpolates bad channels at the epoch level.
%   This function uses the FASTER algorithm to find bad channels for each epoch
%   and then interpolates them using spherical splines.
%
% Syntax:
%   [EEG, out] = prep.interpolate_bad_channels_epoch(EEG, 'param', value, ...)
%
% Input Arguments:
%   EEG         - EEGLAB EEG structure (epoched data).
%
% Optional Parameters (Name-Value Pairs):
%   'LogFile'           - (char | string, default: '')
%                         File path to log the results.
%   'ExcludeLabel'      - (char | string | cellstr, default: {})
%                         Channel labels to exclude from epoch-wise detection/interp.
%
% Output Arguments:
%   EEG         - Modified EEGLAB EEG structure with bad channels interpolated.
%   out         - Structure containing details of the detection:
%                 out.bad_chan_cell: Cell array with bad channel indices for each epoch.
%
% See also: single_epoch_channel_properties, h_epoch_interp_spl, chans2idx

    % ----------------- Parse inputs -----------------
    p = inputParser;
    p.addRequired('EEG', @isstruct);
    p.addParameter('LogFile', '', @(s) ischar(s) || isstring(s));
    p.addParameter('ExcludeLabel', {}, @(x) ischar(x) || isstring(x) || iscell(x));
    p.parse(EEG, varargin{:});
    R = p.Results;

    out = struct();

    % ----------------- ExcludeLabel -> IdxDetect -----------------
    if ~isempty(R.ExcludeLabel)
        excludeIdx = chans2idx(EEG, R.ExcludeLabel);  % your helper
        IdxDetect  = setdiff(1:EEG.nbchan, excludeIdx);
        logPrint(R.LogFile, sprintf( ...
            'Epoch-wise bad-channel detection: excluding labels=%s (idx=%s).', ...
            labels2str(R.ExcludeLabel), mat2str(excludeIdx)));
    else
        excludeIdx = [];
        IdxDetect  = 1:EEG.nbchan;
        logPrint(R.LogFile, 'Epoch-wise bad-channel detection: no excluded channels.');
    end

    logPrint(R.LogFile, 'Identifying bad channels per epoch...');

    % ----------------- Find bad channels per epoch -----------------
    bad_chan_cell = cell(1, EEG.trials);
    for epoch_i = 1:EEG.trials

        % detect only within IdxDetect
        bad_chan_epoch_list = single_epoch_channel_properties(EEG, epoch_i, IdxDetect);

        % tmp_bad_rel is relative to IdxDetect
        tmp_bad_rel = find(min_z(bad_chan_epoch_list) == 1);

        % map to absolute channel indices
        tmp_bad_abs = IdxDetect(tmp_bad_rel);

        bad_chan_cell{epoch_i} = tmp_bad_abs;

        if ~isempty(tmp_bad_abs)
            logPrint(R.LogFile, sprintf( ...
                'Epoch %d - Interpolated chans: %d, Details(idx)=%s', ...
                epoch_i, numel(tmp_bad_abs), mat2str(tmp_bad_abs)));
        end
    end

    % ----------------- Interpolate bad channels -----------------
    logPrint(R.LogFile, 'Interpolating bad channels at the epoch level...');
    EEG = h_epoch_interp_spl(EEG, bad_chan_cell);
    logPrint(R.LogFile, 'Bad channels interpolated successfully.');

    % ----------------- Bookkeeping in EEG.etc -----------------
    out.bad_chan_cell = bad_chan_cell;
    out.excludeIdx    = excludeIdx;
    out.idxDetect     = IdxDetect;

    if ~isfield(EEG, 'etc') || isempty(EEG.etc), EEG.etc = struct(); end
    if ~isfield(EEG.etc, 'EEGdojo') || isempty(EEG.etc.EEGdojo)
        EEG.etc.EEGdojo = struct();
    end
    EEG.etc.EEGdojo.BadChanEpochCell = bad_chan_cell;
    EEG.etc.EEGdojo.BadChanEpoch_ExcludeIdx = excludeIdx;
end

% -------- helper (local) ----------
function s = labels2str(L)
    if ischar(L) || isstring(L)
        s = char(L);
    else
        s = strjoin(cellfun(@char, L, 'uni', false), ',');
    end
end
