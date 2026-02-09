function ok = tf_cache_is_compatible(Out_tfd, args)
%TF_CACHE_IS_COMPATIBLE Validate cached TF output against expected settings.
%
% Args:
%   Out_tfd                  struct returned by analysis.tf_transform
%   args (struct, optional):
%     epoch_window           [tmin tmax] in ms (required)
%     freq_range             [fmin fmax] in Hz (required)
%     expected_params        expected tfr params (struct or name/value cell), optional
%     min_time_coverage      fraction in [0,1], default 0.5
%     time_tolerance_ms      boundary tolerance in ms, default 1
%
% Returns:
%   ok logical scalar

    if nargin < 2 || isempty(args), args = struct(); end
    if ~isfield(args, 'epoch_window'), args.epoch_window = []; end
    if ~isfield(args, 'freq_range'), args.freq_range = []; end
    if ~isfield(args, 'expected_params'), args.expected_params = []; end
    if ~isfield(args, 'min_time_coverage'), args.min_time_coverage = 0.5; end
    if ~isfield(args, 'time_tolerance_ms'), args.time_tolerance_ms = 1; end

    ok = true;
    if ~isstruct(Out_tfd) || ~isfield(Out_tfd, 'meta')
        ok = false;
        return;
    end
    meta = Out_tfd.meta;
    if ~isfield(meta, 'times') || isempty(meta.times)
        ok = false;
        return;
    end
    if ~isfield(meta, 'freqs') || isempty(meta.freqs)
        ok = false;
        return;
    end

    t = meta.times(:);
    f = meta.freqs(:);

    if numel(args.epoch_window) == 2
        ew = args.epoch_window(:).';
        tol = args.time_tolerance_ms;
        if min(t) > ew(1) + tol || max(t) < ew(2) - tol
            ok = false;
            return;
        end
        denom = (ew(2) - ew(1));
        if denom <= 0
            ok = false;
            return;
        end
        coverage = (max(t) - min(t)) / denom;
        if coverage < args.min_time_coverage
            ok = false;
            return;
        end
    end

    if numel(args.freq_range) == 2
        fr = args.freq_range(:).';
        if min(f) > fr(1) || max(f) < fr(2)
            ok = false;
            return;
        end
    end

    if ~isempty(args.expected_params)
        if isfield(meta, 'tfr_params')
            if ~params_match(meta.tfr_params, args.expected_params)
                ok = false;
                return;
            end
        else
            ok = false;
            return;
        end
    end
end

function ok = params_match(saved_params, expected_params)
    ok = true;
    try
        saved = nv_to_struct(saved_params);
        expect = nv_to_struct(expected_params);
        keys = {'freqs', 'cycles', 'timesout', 'padratio'};
        for i = 1:numel(keys)
            k = keys{i};
            if isfield(expect, k)
                if ~isfield(saved, k) || ~isequal(saved.(k), expect.(k))
                    ok = false;
                    return;
                end
            end
        end
    catch
        ok = false;
    end
end

function S = nv_to_struct(nv)
    S = struct();
    if isempty(nv)
        return;
    end
    if isstruct(nv)
        S = nv;
        return;
    end
    if iscell(nv)
        if mod(numel(nv), 2) ~= 0
            return;
        end
        for i = 1:2:numel(nv)
            key = char(string(nv{i}));
            key = lower(key);
            key = regexprep(key, '[^a-z0-9_]', '');
            if isempty(key)
                continue;
            end
            S.(key) = nv{i + 1};
        end
    end
end

