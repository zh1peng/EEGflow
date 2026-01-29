function Out_tfd = run_tfr(dataset, varargin)
% RUN_TFR  Time–frequency decomposition wrapper for epoched EEG (canonical cftt)
% 
%   Out_tfd = analysis.run_tfr(dataset, Name, Value, ...)
% 
% High-level TFR runner for an analysis.Dataset with epoched data. Supports
% EEGLAB's NEWTIMEF, or a custom function handle. Handles optional cropping, 
% baseline normalization, and (optionally) parallelization across 
% subject×condition jobs.
% 
% Canonical internal/output layout is **cftt**:
%   [chan x freq x time x trials] for per-trial arrays,
%   [chan x freq x time]          for trial-averaged arrays.
% 
% -------------------------------------------------------------------------
% REQUIRED DATASET INTERFACE
% -------------------------------------------------------------------------
%   dataset.get_subjects()    -> cellstr of subject IDs
%   dataset.get_conditions()  -> cellstr of condition names
%   dataset.get_data(s,c)     -> [chan x time x trials] double (epoched)
%   dataset.fs                -> scalar sampling rate (Hz)
%   dataset.times             -> [1 x time] ms
%   dataset.chanlocs          -> struct array of channel locations
%   dataset.data.meta         -> arbitrary metadata struct (copied to output)
% 
% -------------------------------------------------------------------------
% NAME–VALUE ARGUMENTS
% -------------------------------------------------------------------------
% 'method'          'eeglab' | @customFn     (default: 'eeglab')
%                   - 'eeglab' : uses EEGLAB's NEWTIMEF (plotting disabled)
%                   - function_handle(EEG, params) -> [tf_complex,freqs,times]
%                     where tf_complex is [chan x f x t x trials], freqs (Hz), times (ms)
% 
% 'params'          Parameters passed to the chosen method.
%                   - For 'eeglab' (CELL of name/value pairs), e.g.:
%                       {'freqs',[2 40], 'cycles',[3 0.8], 'plotersp','off','plotitc','off'}
%                     NOTE: The wrapper ensures plotting is OFF and may adjust
%                     the lowest frequency upward to satisfy cycles×fs ≤ epochLength.
%                   - For function_handle: passed through unchanged to your function.
% 
% 'time_window'     [start_ms end_ms] crop BEFORE TFR (default: [] = no crop).
%                   (API is milliseconds; converted to seconds internally for EEGLAB.)
% 
% 'parallel'        true/false (default: false). When true, each (subject,condition)
%                   is processed in a PARFOR loop (Parallel Computing Toolbox).
% 
% 'baseline_range'  [start_ms end_ms] time window for baseline normalization
%                   (default: [] = no baseline). Must overlap the TFR time grid.
% 
% 'norm_type'       'decibel' (default) | 'subtraction' | 'z-score' | 'percentage'
%                   Baseline is computed over the *method’s* TFR time vector.
% 
% 'keep_trials'     'none' (default) | 'power' | 'phase' | 'complex' | 'all'
%                   Controls whether to store per-trial arrays in the output:
%                   - 'none'    : only trial-averaged power + ITC (memory-light)
%                   - 'power'   : adds .power_trials   [chan x f x t x trials]
%                   - 'phase'   : adds .phase          [chan x f x t x trials]
%                   - 'complex' : adds .tf_complex     [chan x f x t x trials]
%                   - 'all'     : adds all of the above
% 
% 'compute_induced' logical (default: false)
%                   When true, also computes:
%                     .evoked_power  = |TF{mean(EEG across trials)}|^2
%                     .induced_power = max(total_power - evoked_power, 0)
%                   (Both baseline-corrected like total_power when baseline requested.)
% 
% -------------------------------------------------------------------------
% OUTPUT (per subject/condition)
% -------------------------------------------------------------------------
%   Out_tfd                 STRUCT with fields:
%     .sub_<ID>.<cond>.power          [chan x f x t] (trial-averaged total power)
%     .sub_<ID>.<cond>.itc            [chan x f x t]
%     .sub_<ID>.<cond>.ntrials        scalar
%     .sub_<ID>.<cond>.power_trials   [chan x f x t x trials]   (optional)
%     .sub_<ID>.<cond>.phase          [chan x f x t x trials]   (optional)
%     .sub_<ID>.<cond>.tf_complex     [chan x f x t x trials]   (optional)
%     .sub_<ID>.<cond>.evoked_power   [chan x f x t]            (optional)
%     .sub_<ID>.<cond>.induced_power  [chan x f x t]            (optional)
%   Out_tfd.meta            metadata copied from dataset.data.meta plus:
%       .tfr_method (char) 'eeglab'|function name
%       .tfr_params (as provided)
%       .datatype   'time-frequency'
%       .axis       'cftt'
%       .freqs      [1 x f] Hz
%       .times      [1 x t] ms
%       .keep_trials (char)
%       .compute_induced (logical)
% 
% -------------------------------------------------------------------------
% EXAMPLES
% -------------------------------------------------------------------------
% 1) Minimal run (eeglab defaults)
%     Out_tfd = analysis.run_tfr(ds);
% 
% 2) EEGLAB method with parallelization and decibel baseline (−200 to 0 ms)
%     % parpool('threads');    % optional but recommended to avoid cold start
%     eeglab_params = {'freqs',[2 40], 'cycles',[3 0.8]};
%     Out_tfd_eeg = analysis.run_tfr(ds, ...
%         'method','eeglab', 'params',eeglab_params, ...
%         'parallel',true, 'baseline_range',[-200 0], 'norm_type','decibel');
% 
% 3) Crop the epoch before TFR (keep only −500–1500 ms)
%     Out_tfd_crop = analysis.run_tfr(ds, 'time_window',[-500 1500]);
% 
% 4) Custom method handle (expects [chan x f x t x trials] output; cftt)
%     % function [tf_complex, freqs, times] = my_cwt(EEG, params)
%     %   % Build tf_complex (cftt), freqs (Hz), times (ms)
%     % end
%     Out_tfd_custom = analysis.run_tfr(ds, 'method',@my_cwt, 'params',struct('f',[2 80]));
% 
% 5) Quick plotting of one subject/condition
%     f = Out_tfd.meta.freqs;   % Hz
%     t = Out_tfd.meta.times;   % ms
%     S = 'sub_101'; C = 'loss_cue'; ch = ds.find_channels({'Pz'});
%     P = Out_tfd.(S).(C).power;    % [chan x F x T]
%     imagesc(t, f, squeeze(P(ch,:,:))); axis xy
%     xlabel('Time (ms)'); ylabel('Freq (Hz)'); title('Power (Pz)'); colorbar
% 
% -------------------------------------------------------------------------
% THEORY NOTE (evoked vs total vs induced)
% -------------------------------------------------------------------------
%   TF of averaged ERP (evoked): |TF{mean(x_k)}|^2 → phase-locked only.
%   Average of single-trial TF (total): mean_k |TF{x_k}|^2 → evoked + induced.
%   Induced ≈ total − evoked (with same baseline).
% 
% -------------------------------------------------------------------------
% TROUBLESHOOTING & TIPS
% -------------------------------------------------------------------------
% • EEGLAB "Not enough data points" at low frequencies:
%   - With cycles=[3 0.8] and short epochs, ~1–2 Hz may be infeasible.
%   - This wrapper auto-raises the lowest frequency to a safe value (warning).
%   - Alternatively, lengthen epochs or reduce cycles (e.g., cycles=[2 0.5]).
% 
% • 'params' type must match method:
%     - 'eeglab' → CELL of name/value pairs
%     - @custom  → as your function expects (must return cftt)
% 
% • Baseline window must overlap the TFR time vector. If not, baseline correction
%   is skipped with a warning.
% 
% • Memory: Per-trial arrays are large. Use 'keep_trials','none' unless needed.
% 
% SEE ALSO: newtimef (EEGLAB), spectrogram, cwt
%
    % --- Input Parser ---
    p = inputParser;
    addRequired(p, 'dataset', @(x) isa(x, 'analysis.Dataset'));
    addParameter(p, 'method', 'eeglab', @(x) ischar(x) || isa(x, 'function_handle'));
    addParameter(p, 'params', {}, @(x) isstruct(x) || iscell(x) || isempty(x));
    addParameter(p, 'time_window', [], @(x) isempty(x) || (isnumeric(x) && numel(x) == 2));
    addParameter(p, 'parallel', false, @islogical);
    addParameter(p, 'baseline_range', [], @(x) isempty(x) || (isnumeric(x) && numel(x) == 2));
    addParameter(p, 'norm_type', 'decibel', @ischar);
    addParameter(p, 'keep_trials', 'none', @(s) any(strcmpi(s, {'none','power','phase','complex','all'})));
    addParameter(p, 'compute_induced', false, @islogical);
    parse(p, dataset, varargin{:});

    tfr_method       = p.Results.method;
    tfr_params_in    = p.Results.params;
    time_window_ms   = p.Results.time_window;
    use_parallel     = p.Results.parallel;
    baseline_range   = p.Results.baseline_range;
    norm_type        = p.Results.norm_type;
    keep_trials      = lower(p.Results.keep_trials);
    compute_induced  = p.Results.compute_induced;

    method_name = tfr_method; if isa(tfr_method, 'function_handle'), method_name = func2str(tfr_method); end
    fprintf('Starting TFR for %d subjects using method: %s...\n', numel(dataset.subjects), method_name);

    % --- Setup for processing ---
    Out_tfd = struct();
    all_subjects   = dataset.get_subjects();
    all_conditions = dataset.get_conditions();

    proc_data = struct();
    for s = 1:numel(all_subjects)
        for c = 1:numel(all_conditions)
            key = ['s' all_subjects{s} 'c' all_conditions{c}];
            proc_data.(key).subject_id = all_subjects{s};
            proc_data.(key).condition  = all_conditions{c};
        end
    end
    proc_keys = fieldnames(proc_data);

    % --- Main Loop (Sequential or Parallel) ---
    if use_parallel
        fprintf('Running in parallel...\n');
        results_cell = cell(1, numel(proc_keys));
        parfor i = 1:numel(proc_keys)
            results_cell{i} = process_single_tfr(proc_keys{i}, proc_data.(proc_keys{i}), ...
                dataset, tfr_method, tfr_params_in, time_window_ms, baseline_range, norm_type, keep_trials, compute_induced);
        end
    else
        fprintf('Running sequentially...\n');
        results_cell = cell(1, numel(proc_keys));
        for i = 1:numel(proc_keys)
            results_cell{i} = process_single_tfr(proc_keys{i}, proc_data.(proc_keys{i}), ...
                dataset, tfr_method, tfr_params_in, time_window_ms, baseline_range, norm_type, keep_trials, compute_induced);
        end
    end

    % --- Consolidate Results ---
    freqs = []; times = [];
    for i = 1:numel(results_cell)
        res = results_cell{i};
        if ~isempty(res) && isfield(res, 'power')
            sub_field = ['sub_' res.subject_id];
            Out_tfd.(sub_field).(res.condition).power    = res.power;     % [chan x f x t]
            Out_tfd.(sub_field).(res.condition).itc      = res.itc;       % [chan x f x t]
            Out_tfd.(sub_field).(res.condition).ntrials  = res.ntrials;

            if isfield(res,'power_trials') && ~isempty(res.power_trials)
                Out_tfd.(sub_field).(res.condition).power_trials = res.power_trials;
            end
            if isfield(res,'phase') && ~isempty(res.phase)
                Out_tfd.(sub_field).(res.condition).phase = res.phase;
            end
            if isfield(res,'tf_complex') && ~isempty(res.tf_complex)
                Out_tfd.(sub_field).(res.condition).tf_complex = res.tf_complex;
            end
            if isfield(res,'evoked_power') && ~isempty(res.evoked_power)
                Out_tfd.(sub_field).(res.condition).evoked_power  = res.evoked_power;
            end
            if isfield(res,'induced_power') && ~isempty(res.induced_power)
                Out_tfd.(sub_field).(res.condition).induced_power = res.induced_power;
            end

            if isempty(freqs), freqs = res.freqs; end
            if isempty(times), times = res.times; end
        end
    end

    % --- Finalize Metadata ---
    Out_tfd.meta = dataset.data.meta;
    Out_tfd.meta.tfr_method      = method_name;
    Out_tfd.meta.tfr_params      = tfr_params_in;
    Out_tfd.meta.datatype        = 'time-frequency';
    Out_tfd.meta.axis            = 'cftt';
    Out_tfd.meta.freqs           = freqs;
    Out_tfd.meta.times           = times;
    Out_tfd.meta.keep_trials     = keep_trials;
    Out_tfd.meta.compute_induced = compute_induced;

    fprintf('Time-Frequency Decomposition complete.\n');
end

% === Worker ===
function result = process_single_tfr(key, data, dataset, tfr_method, tfr_params_in, time_window_ms, baseline_range, norm_type, keep_trials, compute_induced)
    fprintf('Processing: Subject %s, Condition %s\n', data.subject_id, data.condition);
    result = struct('key', key, 'subject_id', data.subject_id, 'condition', data.condition);

    % Build a minimal EEG-like struct
    EEG = eeg_emptyset();
    EEG.data    = dataset.get_data(data.subject_id, data.condition); % [chan x time x trials]
    if isempty(EEG.data), result = []; return; end

    EEG.srate   = dataset.fs;
    EEG.nbchan  = size(EEG.data, 1);
    EEG.pnts    = size(EEG.data, 2);
    EEG.trials  = size(EEG.data, 3);
    EEG.times   = dataset.times;   % ms
    EEG.chanlocs= dataset.chanlocs;
    EEG.xmin    = EEG.times(1)/1000;  % sec
    EEG.xmax    = EEG.times(end)/1000;

    % Optional cropping (API is ms, EEGLAB expects sec)
    if ~isempty(time_window_ms)
        EEG = pop_select(EEG, 'time', time_window_ms/1000);
        EEG.pnts  = size(EEG.data, 2);
        EEG.times = linspace(time_window_ms(1), time_window_ms(2), EEG.pnts); % ms
        EEG.xmin  = EEG.times(1)/1000;
        EEG.xmax  = EEG.times(end)/1000;
    end

    try
        % ---------- Route by method: build tf_complex (cftt), freqs, times ----------
        if ischar(tfr_method)
            switch lower(tfr_method)
                case 'eeglab'
                    [cyclesArg, nvParams] = massage_newtimef_params(EEG, tfr_params_in);
                    freqs = []; times = []; tf_complex = [];

                    for iChan = 1:EEG.nbchan
                        dat = squeeze(EEG.data(iChan,:,:));   % [time x trials]
                        if size(dat,1) ~= EEG.pnts, dat = dat.' ; end % ensure [frames x trials]

                        [~,~,~,times_out,freqs_out,~,~,alltfX] = ...
                            newtimef(dat, EEG.pnts, [EEG.xmin EEG.xmax]*1000, EEG.srate, cyclesArg, nvParams{:}); %#ok<ASGLU>

                        if isempty(freqs)
                            freqs = freqs_out(:).';
                            times = times_out(:).';
                            tf_complex = zeros(EEG.nbchan, numel(freqs), numel(times), EEG.trials, 'like', alltfX);
                        end
                        tf_complex(iChan,:,:,:) = alltfX; % alltfX: [f x t x trials]
                    end
                otherwise
                    error('Unknown built-in method: %s', tfr_method);
            end

        elseif isa(tfr_method, 'function_handle')
            [tf_complex, freqs, times] = feval(tfr_method, EEG, tfr_params_in); % expect cftt
            % Optional shape auto-detect (if user returned [c x t x f x tr])
            if ndims(tf_complex) == 4 && size(tf_complex,2) == numel(times) && size(tf_complex,3) == numel(freqs)
                tf_complex = permute(tf_complex, [1 3 2 4]); % -> cftt
            end
        else
            error('Unsupported method specifier.');
        end

        % ---------- Baseline Correction on per-trial power ----------
        power_data = abs(tf_complex).^2; % [chan x f x t x trials]
        if ~isempty(baseline_range)
            power_data = func_BL_norm(power_data, times, baseline_range, norm_type);
        end

        % ---------- Outputs (trial-averaged + optional per-trial) ----------
        result.ntrials = size(power_data, 4);
        result.power   = mean(power_data, 4);                        % [chan x f x t]
        result.itc     = abs(mean(exp(1i * angle(tf_complex)), 4));  % [chan x f x t]
        result.freqs   = freqs;
        result.times   = times;

        switch keep_trials
            case 'power'
                result.power_trials = power_data;
            case 'complex'
                result.tf_complex   = tf_complex;
            case 'phase'
                result.phase        = angle(tf_complex);
            case 'all'
                result.power_trials = power_data;
                result.tf_complex   = tf_complex;
                result.phase        = angle(tf_complex);
        end

        % ---------- Optional: evoked & induced ----------
        if compute_induced
            evoked_power = compute_evoked_power(EEG, tfr_method, tfr_params_in, freqs, times, baseline_range, norm_type);
            % Ensure size/time match (interpolate if needed)
            if ~isequal(size(evoked_power), size(result.power))
                % Attempt linear interpolation on time axis
                warning('Evoked power size mismatch; attempting interpolation to align time axis.');
                evoked_power = interp_evoked_to_times(evoked_power, times, result.times);
            end
            induced_power = result.power - evoked_power;
            induced_power(induced_power<0) = 0; % clip tiny negatives
            result.evoked_power  = evoked_power;
            result.induced_power = induced_power;
        end

    catch ME
        warning('TFR failed for Subject %s, Condition %s. Error: %s', data.subject_id, data.condition, ME.message);
        result = [];
    end
end

% --- Helpers ---

function [cyclesArg, nvParamsOut] = massage_newtimef_params(EEG, params_in)
    % Extract/Default: cycles & freqs; clamp lowest freq if needed; ensure no plotting
    params = params_in; if isempty(params), params = {}; end
    if isstruct(params), error('For method ''eeglab'', ''params'' should be a cell array of name-value pairs.'); end
    if iscell(params)
        params = params(:).';
    end

    cyclesArg = [3 0.8];
    freqs     = [1 40];

    idx = find(strcmpi(params, 'cycles'), 1); if ~isempty(idx), cyclesArg = params{idx+1}; params([idx idx+1]) = []; end
    idx = find(strcmpi(params, 'freqs'),  1); if ~isempty(idx), freqs     = params{idx+1}; end

    % guard lowest frequency (wavelet length <= epoch)
    if numel(freqs) == 2
        f_lo = freqs(1); f_hi = freqs(2);
        c0   = cyclesArg(1);
        fmin_ok = (c0 * EEG.srate / EEG.pnts) * 1.05;  % small margin
        if f_lo < fmin_ok
            new_lo = max(fmin_ok, 2);
            warning('Adjusted lowest frequency from %.3g Hz to %.3g Hz to satisfy epoch/cycles constraint.', f_lo, new_lo);
            freqs = [new_lo, f_hi];
        end
    else
        c0   = cyclesArg(1);
        fmin_ok = (c0 * EEG.srate / EEG.pnts) * 1.05;
        keep = freqs >= fmin_ok;
        if ~all(keep)
            warning('Removed %d frequencies below %.3g Hz due to epoch/cycles constraint.', sum(~keep), fmin_ok);
            freqs = freqs(keep);
        end
    end

    % ensure plotting is off (faster / parfor-safe)
    if ~any(strcmpi(params, 'plotersp')), params = [params, {'plotersp','off'}]; end
    if ~any(strcmpi(params, 'plotitc')),  params = [params, {'plotitc','off'}];  end
    % write back freqs
    j = find(strcmpi(params, 'freqs'), 1);
    if isempty(j), params = [params, {'freqs', freqs}]; else, params{j+1} = freqs; end

    nvParamsOut = params;
end

function normTFdata = func_BL_norm(TFdata, tvec_ms, baselineRange, normType)
    % TFdata: [chan x f x t x trials]
    if nargin < 4 || isempty(normType), normType = 'decibel'; end
    valid = {'decibel','subtraction','z-score','percentage'};
    if ~ismember(lower(normType), valid)
        error('Invalid normType. Choose: decibel | subtraction | z-score | percentage');
    end

    tvec_ms = tvec_ms(:).';
    baseMask = tvec_ms >= baselineRange(1) & tvec_ms <= baselineRange(2);
    if ~any(baseMask)
        warning('Baseline window [%g %g] ms contains no TFR time points. Skipping baseline correction.', baselineRange(1), baselineRange(2));
        normTFdata = TFdata; return;
    end

    baselineData = TFdata(:,:,baseMask,:);                 % [chan x f x tb x trials]
    meanBaseline = mean(baselineData, 3);                  % [chan x f x 1 x trials]

    % Avoid division by zero
    epsMB = meanBaseline;
    epsMB(epsMB==0) = eps; %#ok<*NASGU>

    switch lower(normType)
        case 'decibel'
            normTFdata = 10 * log10(bsxfun(@rdivide, TFdata, meanBaseline));
        case 'subtraction'
            normTFdata = bsxfun(@minus, TFdata, meanBaseline);
        case 'z-score'
            stdBaseline = std(baselineData, 0, 3);         % [chan x f x 1 x trials]
            stdBaseline(stdBaseline==0) = eps;
            normTFdata  = bsxfun(@rdivide, bsxfun(@minus, TFdata, meanBaseline), stdBaseline);
        case 'percentage'
            meanBaseline(meanBaseline==0) = eps;
            normTFdata  = bsxfun(@rdivide, bsxfun(@minus, TFdata, meanBaseline), meanBaseline) * 100;
    end
end

function evoked_power = compute_evoked_power(EEG, tfr_method, tfr_params_in, freqs_ref, times_ref, baseline_range, norm_type)
    % Compute |TF{ERP}|^2 as evoked power (cftt collapsed over trials)
    ERP = mean(EEG.data, 3);                    % [chan x time]
    ERP_EEG         = EEG;
    ERP_EEG.data    = reshape(ERP, [EEG.nbchan, EEG.pnts, 1]);
    ERP_EEG.trials  = 1;

    if ischar(tfr_method)
        switch lower(tfr_method)
            case 'eeglab'
                [cyclesArg, nvParams] = massage_newtimef_params(ERP_EEG, tfr_params_in);
                evk = zeros(ERP_EEG.nbchan, numel(freqs_ref), numel(times_ref)); % c f t
                for iChan = 1:ERP_EEG.nbchan
                    dat = squeeze(ERP_EEG.data(iChan,:,:)); % [time x 1]
                    if size(dat,1) ~= ERP_EEG.pnts, dat = dat.' ; end
                    [~,~,~,times_out,freqs_out,~,~,alltfX] = ...
                        newtimef(dat, ERP_EEG.pnts, [ERP_EEG.xmin ERP_EEG.xmax]*1000, ERP_EEG.srate, cyclesArg, nvParams{:}); %#ok<ASGLU>
                    tf_e = abs(alltfX).^2; % [f x t]
                    % Align to reference grid if needed
                    evk(iChan,:,:) = align_tf_to_ref(tf_e, freqs_out(:).', times_out(:).', freqs_ref, times_ref);
                end
                evoked_power = evk;
            otherwise
                error('compute_induced only implemented for built-in methods and custom function handles.');
        end

    elseif isa(tfr_method, 'function_handle')
        [tf_complex_e, freqs_e, times_e] = feval(tfr_method, ERP_EEG, tfr_params_in); % expect cftt
        if ndims(tf_complex_e)==4 && size(tf_complex_e,2)==numel(times_e) && size(tf_complex_e,3)==numel(freqs_e)
            tf_complex_e = permute(tf_complex_e, [1 3 2 4]); % -> cftt
        end
        tf_e = abs(tf_complex_e).^2;   % [chan x f x t x 1]
        evoked_power = tf_e(:,:,:,1);  % [chan x f x t]
        % Align to ref grid if needed
        if (~isequal(freqs_e(:).', freqs_ref)) || (~isequal(times_e(:).', times_ref))
            evoked_power = align_tfa_to_ref(evoked_power, freqs_e(:).', times_e(:).', freqs_ref, times_ref);
        end

    else
        error('Unsupported method for compute_evoked_power.');
    end

    % Baseline evoked power if requested
    if ~isempty(baseline_range)
        tmp = func_BL_norm(reshape(evoked_power, [size(evoked_power) 1]), times_ref, baseline_range, norm_type);
        evoked_power = tmp(:,:,:,1);
    end
end

function times = build_tfa_times(EEG, tvec_out, tlen)
    if ~isempty(tvec_out) && numel(tvec_out) == tlen
        if all(abs(diff(tvec_out) - 1) < 1e-6) && max(tvec_out) <= EEG.pnts + 1
            times = EEG.times(1) + (tvec_out - 1) * (1000/EEG.srate);
        else
            if max(abs(tvec_out)) < 30 % seconds
                times = 1000 * tvec_out(:).';
            else
                times = tvec_out(:).';
            end
        end
    else
        times = linspace(EEG.times(1), EEG.times(end), tlen);
    end
end

function evk = align_tf_to_ref(tf_e, freqs_src, times_src, freqs_ref, times_ref)
    % tf_e: [f x t], align to ref grids by linear interpolation
    if isequal(freqs_src, freqs_ref) && isequal(times_src, times_ref)
        evk = tf_e;
        return;
    end
    % Interpolate along time first
    if ~isequal(times_src, times_ref)
        tf_e = interp1(times_src, tf_e.', times_ref, 'linear', 'extrap').'; % now [f x t_ref]
    end
    % Interpolate along frequency
    if ~isequal(freqs_src, freqs_ref)
        evk = interp1(freqs_src, tf_e, freqs_ref, 'linear', 'extrap');      % [f_ref x t_ref]
    else
        evk = tf_e;
    end
end

function evoked_power = align_tfa_to_ref(tf_e_cft, freqs_src, times_src, freqs_ref, times_ref)
    % tf_e_cft: [chan x f x t]
    [C, F, T] = size(tf_e_cft);
    evoked_power = zeros(C, numel(freqs_ref), numel(times_ref), 'like', tf_e_cft);
    for ch = 1:C
        evk = squeeze(tf_e_cft(ch,:,:));                 % [f x t]
        evk = align_tf_to_ref(evk, freqs_src, times_src, freqs_ref, times_ref);
        evoked_power(ch,:,:) = evk;
    end
end

function evoked_power = interp_evoked_to_times(evoked_power, times_src, times_ref)
    % evoked_power: [chan x f x t_src] → interpolate to t_ref
    [C,F,~] = size(evoked_power);
    out = zeros(C,F,numel(times_ref), 'like', evoked_power);
    for ch = 1:C
        out(ch,:,:) = interp1(times_src, squeeze(evoked_power(ch,:,:)).', times_ref, 'linear', 'extrap').';
    end
    evoked_power = out;
end
