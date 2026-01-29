function [bad_idx_abs, info] = cleanraw_rejchan(EEG, varargin)
% CLEANRAW_REJCHAN  Detect bad channels using CleanRaw-like measures.
%
% Usage:
%   bad_idx = cleanraw_rejchan(EEG, 'measure','flatline', 'threshold',5);
%   bad_idx = cleanraw_rejchan(EEG, 'measure','CleanChan', ...
%                               'chancorr_crit',0.8, 'line_crit',4, 'elec',1:64);
%
% Inputs (name/value):
%   'measure'        - 'flatline' | 'CleanChan' (default 'flatline')
%   'threshold'      - flatline threshold (sec), default 5
%   'chancorr_crit'  - CleanChan correlation cutoff, default 0.8
%   'line_crit'      - CleanChan line-noise cutoff, default 4
%   'elec'           - indices or logical mask of channels to analyze (default: all)
%   'highpass'       - [low high] band for drift cleaning (default [0.25 0.75]); [] = skip
%   'maxbadtime'     - max broken-time proportion for CleanChan (default 0.5)
%   'num_samples'    - min corr samples for CleanChan (default 50)
%   'Verbose'        - true/false (default false)
%
% Output:
%   bad_idx_abs      - bad channel indices (absolute in EEG space)
%   info             - struct with details (optional)
%
% Assumes availability of:
%   clean_drifts, clean_flatlines, clean_channels (Clean Rawdata family)

    % ---------- Parse inputs ----------
    p = inputParser;
    p.addRequired('EEG', @isstruct);
    p.addParameter('measure', 'flatline', @(x) any(strcmpi(x, {'flatline','CleanChan'})));
    p.addParameter('threshold', 5, @(x) isnumeric(x) && isscalar(x) && x>=0);
    p.addParameter('chancorr_crit', 0.8, @isnumeric);
    p.addParameter('line_crit', 4, @isnumeric);
    p.addParameter('elec', [], @(x) isnumeric(x) || islogical(x));
    p.addParameter('highpass', [0.25 0.75], @(x) isempty(x) || (isnumeric(x) && numel(x)==2));
    p.addParameter('maxbadtime', 0.5, @(x) isnumeric(x) && isscalar(x) && x>=0 && x<=1);
    p.addParameter('num_samples', 50, @(x) isnumeric(x) && isscalar(x) && x>=0);
    p.addParameter('Verbose', false, @(x) islogical(x) && isscalar(x));
    p.parse(EEG, varargin{:});
    R = p.Results;

    % Resolve channel subset
    nb = EEG.nbchan;
    if isempty(R.elec)
        elec = 1:nb;
    elseif islogical(R.elec)
        elec = find(R.elec);
    else
        elec = R.elec(:).';
    end
    elec = elec(elec>=1 & elec<=nb);  % bound-check
    if isempty(elec)
        error('cleanraw_rejchan:EmptySelection', 'No valid channels selected in ''elec''.');
    end

    % Prepare temporary EEG with selected channels (no side-effects)
    EEGtmp = pop_select(EEG, 'channel', elec);

    % Optional drift cleaning
    if ~isempty(R.highpass)
        assert(exist('clean_drifts','file')==2, 'clean_drifts not found on path.');
        EEGtmp = clean_drifts(EEGtmp, R.highpass);
    end

    % Initialize
    bad_rel = [];
    mask_rel = true(1, numel(elec)); % 1=kept, 0=bad

    % ---------- Dispatch ----------
    switch lower(R.measure)
        case 'flatline'
            if R.Verbose
                fprintf('CleanRaw: flatline detection (%.2f s)\n', R.threshold);
            end
            assert(exist('clean_flatlines','file')==2, 'clean_flatlines not found on path.');
            EEGtmp2 = clean_flatlines(EEGtmp, R.threshold);

            % Expect a clean_channel_mask in etc
            if isfield(EEGtmp2,'etc') && isfield(EEGtmp2.etc,'clean_channel_mask') ...
                    && ~isempty(EEGtmp2.etc.clean_channel_mask)
                mask_rel = logical(EEGtmp2.etc.clean_channel_mask(:)).';
                bad_rel  = find(~mask_rel);
            else
                bad_rel = []; % if the tool didn't flag any channels
            end

        case 'cleanchan'
            if R.Verbose
                fprintf('CleanRaw: noisy channels (corr>=%.2f, line>=%.2f, maxbad=%.2f, nsamp=%d)\n', ...
                        R.chancorr_crit, R.line_crit, R.maxbadtime, R.num_samples);
            end
            assert(exist('clean_channels','file')==2, 'clean_channels not found on path.');

            % Signature commonly returns [EEGout, removed_mask]
            [~, removed_channels] = clean_channels(EEGtmp, ...
                R.chancorr_crit, R.line_crit, [], R.maxbadtime, R.num_samples);

            if isempty(removed_channels)
                bad_rel = [];
            else
                % removed_channels often is logical/0-1 per channel in EEGtmp
                removed_channels = removed_channels(:).';
                bad_rel = find(removed_channels==1);
                mask_rel = ~logical(removed_channels);
            end
    end

    % Map relative -> absolute indices in original EEG channel space
    bad_rel = unique(bad_rel, 'stable');
    bad_idx_abs = elec(bad_rel);

    % Optional info out
    if nargout > 1
        info = struct();
        info.measure       = R.measure;
        info.params        = R;
        info.elec_abs      = elec;                     % absolute indices analyzed
        info.mask_rel      = mask_rel(:).';            % mask within elec
        info.bad_rel       = bad_rel(:).';
        info.bad_abs       = bad_idx_abs(:).';
        info.bad_labels    = idx2chans(EEG, bad_idx_abs);
        info.n_bad         = numel(bad_idx_abs);
    end

    % Verbose printout (optional)
    if R.Verbose
        if isempty(bad_idx_abs)
            fprintf('No bad channels detected (%s).\n', lower(R.measure));
        else
            fprintf('Bad channels (%s): %s\n', lower(R.measure), strjoin(info.bad_labels(~cellfun('isempty',info.bad_labels)), ', '));
        end
    end
end