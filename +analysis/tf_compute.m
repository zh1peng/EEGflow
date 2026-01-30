function state = tf_compute(state, args, meta)
    % Args:
    %   tlimits (ms), freqs (Hz), cycles, padratio (newtimef params)
    %   baseline (ms), timesout (num points)

    if nargin < 2, args = struct(); end
    defaults = struct('tlimits', [], 'freqs', [3 30], 'cycles', [3 0.5], ...
                      'timesout', 200, 'padratio', 2, 'baseline', NaN);
    f = fieldnames(defaults);
    for i = 1:numel(f)
        if ~isfield(args, f{i}), args.(f{i}) = defaults.(f{i}); end
    end

    state_check(state);
    groups = fieldnames(state.Selection.Groups);
    if isempty(groups), error('No groups defined.'); end
    if isempty(state.Selection.Conditions), error('No conditions selected.'); end
    if ~exist('newtimef', 'file')
        error('newtimef not found. Ensure EEGLAB is on the MATLAB path.');
    end

    if nargin >= 3 && isfield(meta, 'validate_only') && meta.validate_only
        fprintf('[ValidateOnly] newtimef with freqs=[%g %g], cycles=[%g %g]\n', ...
            args.freqs(1), args.freqs(2), args.cycles(1), args.cycles(2));
        return;
    end

    times_ms = state.Dataset.times;
    if isempty(times_ms)
        error('Dataset.times is empty.');
    end
    if isempty(args.tlimits)
        tlimits = [times_ms(1) times_ms(end)];
    else
        tlimits = args.tlimits;
    end
    srate = state.Dataset.fs;

    fprintf('Computing Time-Frequency (newtimef)...\n');

    for g = 1:numel(groups)
        subs = state.Selection.Groups.(groups{g});
        for s = 1:numel(subs)
            sid = subs{s};
            sfield = state_subject_field(state, sid);
            for c = 1:numel(state.Selection.Conditions)
                cond = state.Selection.Conditions{c};

                data = state.Dataset.get_data(sfield, cond); % [chan x time x trials]
                if isempty(data), continue; end

                [nChans, nPnts, ~] = size(data);
                if ~isfield(state.Results, 'TF')
                    state.Results.TF = struct();
                end
                if ~isfield(state.Results.TF, sfield)
                    state.Results.TF.(sfield) = struct();
                end

                [~, ~, ~, tf_times, tf_freqs] = newtimef( ...
                    data(1, :, :), nPnts, tlimits, srate, args.cycles, ...
                    'freqs', args.freqs, 'timesout', args.timesout, 'padratio', args.padratio, ...
                    'baseline', args.baseline, 'plotersp', 'off', 'plotitc', 'off', 'verbose', 'off');

                ersp_data = zeros(nChans, numel(tf_freqs), numel(tf_times));
                for ch = 1:nChans
                    [ersp, ~, ~, ~, ~] = newtimef( ...
                        data(ch, :, :), nPnts, tlimits, srate, args.cycles, ...
                        'freqs', args.freqs, 'timesout', args.timesout, 'padratio', args.padratio, ...
                        'baseline', args.baseline, 'plotersp', 'off', 'plotitc', 'off', 'verbose', 'off');
                    ersp_data(ch, :, :) = ersp;
                end

                state.Results.TF.(sfield).(cond).power = ersp_data;
                state.Results.TF.(sfield).(cond).times = tf_times;
                state.Results.TF.(sfield).(cond).freqs = tf_freqs;
            end
        end
    end
    fprintf('TF Computation Done.\n');
end
