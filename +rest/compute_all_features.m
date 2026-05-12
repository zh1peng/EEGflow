function state = compute_all_features(state, args, meta)
%COMPUTE_ALL_FEATURES Compute resting-state features (state-based middleware).
%
% This is a refactor of the legacy params-driven pipeline into EEGflow's
% state+middleware style (similar to +prep).
%
% Flow/state contract
%   Required input state fields:
%     - state.EEG (epoched EEGLAB struct; trials are treated as epochs)
%   Updated/created state fields:
%     - state.rest.features (optional; controlled by KeepInState)
%     - state.rest.output_file (if SaveMat)
%     - state.history
%
% Args (subset):
%   - LogFile (char|string)             optional
%   - OutputPath (char|string)          optional (defaults to state.cfg.Output.filepath or pwd)
%   - OutputBaseName (char|string)      optional (defaults to state.cfg.Output.basename or EEG.setname)
%   - SaveMat (logical)                default true
%   - KeepInState (logical)            default true
%   - nTrial_treshold (numeric scalar) default 10
%   - FreqBand (struct)                default standard bands
%   - HeadModelPath / HeadModel        required when ComputeSource=true
%   - AtlasPath or SourcePos           required when ComputeSource=true
%   - TemplateElecFile / Elec          recommended when ComputeSource=true
%   - ComputeSource (logical)          default true
%   - ComputeDwpli (logical)           default true
%   - ComputeAec (logical)             default true
%   - ComputeGraph (logical)           default true (skipped if GRETNA not available)
%   - KeepSource (logical)             default false (source structs can be very large)
%   - ComputeSourcePower (logical)     default true
%       If true, store a per-ROI source power estimate (inside nodes) for
%       each band. This enables source-space power visualizations without
%       keeping the full FieldTrip "source" struct.
%   - RemoveAperiodic (logical)        default false
%       If true, compute sensor-space spectra and peak frequency both with
%       and without aperiodic (1/f) component removal.
%   - AperiodicFitRange (1x2 numeric)  default [2 40]
%   - AtlasNetworkOrder (cellstr)      default Schaefer7 order
%       Used for network-block parcellation in plotting utilities.
%
% Notes:
%   - Requires FieldTrip for most computations.
%   - Graph measures require GRETNA; if missing, graph metrics are skipped with a warning.

    if nargin < 1 || isempty(state), state = struct(); end
    if nargin < 2 || isempty(args),  args = struct();  end
    if nargin < 3 || isempty(meta),  meta = struct();  end

    op = 'compute_all_features';
    cfg = state_get_config(state, op);
    params = state_merge(cfg, args);

    % -------- defaults --------
    % EEGflow expects analysis parameters to be provided via config JSON
    % (state.cfg + step args). Avoid relying on a code-side "params template".
    defaultBands = struct();

    p = inputParser;
    p.addRequired('EEG', @isstruct);
    p.addParameter('LogFile', '', @(s) ischar(s) || isstring(s));
    p.addParameter('OutputPath', '', @(s) ischar(s) || isstring(s));
    p.addParameter('OutputBaseName', '', @(s) ischar(s) || isstring(s));
    p.addParameter('SaveMat', true, @(x) islogical(x) && isscalar(x));
    p.addParameter('KeepInState', true, @(x) islogical(x) && isscalar(x));

    % legacy-compatible field name (typo preserved)
    p.addParameter('nTrial_treshold', 10, @(x) isnumeric(x) && isscalar(x) && x >= 0);
    p.addParameter('MinTrials', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 0));

    % spectral / connectivity params (legacy names)
    p.addParameter('FreqRes', 0.1, @(x) isnumeric(x) && isscalar(x) && x > 0);
    p.addParameter('PowerFreqStep', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));
    p.addParameter('PowerFreqRange', [1 100], @(x) isnumeric(x) && numel(x) == 2 && all(isfinite(x)) && x(2) > x(1));
    p.addParameter('PowerFoi', [], @(x) isempty(x) || (isnumeric(x) && isvector(x) && all(isfinite(x))));
    p.addParameter('PeakBand', 'alpha', @(s) ischar(s) || isstring(s));
    p.addParameter('Pad', [], @(x) isempty(x) || ischar(x) || isstring(x) || (isnumeric(x) && isscalar(x) && x > 0));
    p.addParameter('Taper', 'dpss', @(s) ischar(s) || isstring(s));
    p.addParameter('Tapsmofrq', 1, @(x) isnumeric(x) && isscalar(x) && x > 0);
    p.addParameter('FreqBand', defaultBands, @isstruct);
    p.addParameter('FreqResConnectivity', 0.5, @(x) isnumeric(x) && isscalar(x) && x > 0);

    % aperiodic (1/f) analysis
    p.addParameter('RemoveAperiodic', false, @(x) islogical(x) && isscalar(x));
    p.addParameter('AperiodicFitRange', [2 40], @(x) isnumeric(x) && numel(x) == 2 && all(isfinite(x)) && x(1) > 0 && x(2) > x(1));

    % source / models
    p.addParameter('ComputeSource', true, @(x) islogical(x) && isscalar(x));
    p.addParameter('HeadModelPath', '', @(s) ischar(s) || isstring(s));
    p.addParameter('HeadModel', [], @(x) isempty(x) || isstruct(x));
    p.addParameter('AtlasPath', '', @(s) ischar(s) || isstring(s));
    p.addParameter('SourcePos', [], @(x) isempty(x) || (isnumeric(x) && size(x, 2) == 3));
    p.addParameter('SurfaceModelPath', '', @(s) ischar(s) || isstring(s));
    p.addParameter('TemplateElecFile', '', @(s) ischar(s) || isstring(s));
    p.addParameter('Elec', [], @(x) isempty(x) || isstruct(x));
    p.addParameter('Unit', 'mm', @(s) ischar(s) || isstring(s));

    % per-band measures
    p.addParameter('ComputeDwpli', true, @(x) islogical(x) && isscalar(x));
    p.addParameter('ComputeAec', true, @(x) islogical(x) && isscalar(x));
    p.addParameter('ComputeGraph', true, @(x) islogical(x) && isscalar(x));
    p.addParameter('KeepSource', false, @(x) islogical(x) && isscalar(x));
    p.addParameter('ComputeSourcePower', true, @(x) islogical(x) && isscalar(x));

    % Parcellation (plotting convenience; computed even if you use SourcePos)
    p.addParameter('AtlasNetworkOrder', {'Vis','SomMot','DorsAttn','SalVentAttn','Limbic','Cont','Default'}, ...
        @(x) iscellstr(x) || isstring(x));

    % GRETNA params (only used if ComputeGraph=true and dependency available)
    p.addParameter('GRETNA_s1', 0.05, @(x) isnumeric(x) && isscalar(x));
    p.addParameter('GRETNA_s2', 0.3, @(x) isnumeric(x) && isscalar(x));
    p.addParameter('GRETNA_deltas', 0.02, @(x) isnumeric(x) && isscalar(x) && x > 0);
    p.addParameter('GRETNA_n', 1000, @(x) isnumeric(x) && isscalar(x) && x > 0);

    % Optional dependency auto-wiring (avoids hardcoding addpath in scripts)
    p.addParameter('AutoAddDeps', true, @(x) islogical(x) && isscalar(x));
    p.addParameter('FieldTripRoot', '', @(s) ischar(s) || isstring(s));
    p.addParameter('GretnaRoot', '', @(s) ischar(s) || isstring(s));

    nv = state_struct2nv(params);

    state_require_eeg(state, op);
    p.parse(state.EEG, nv{:});
    R = rest.normalize_params(p.Results);

    if ~isfield(R, 'FreqBand') || ~isstruct(R.FreqBand) || isempty(fieldnames(R.FreqBand))
        error('rest:compute_all_features:MissingFreqBand', ...
            'FreqBand is required. Provide it in your rest config JSON (step args) as a struct, e.g., {\"alpha\":[8,12]}.');
    end

    if isfield(meta, 'validate_only') && meta.validate_only
        deps = struct();
        deps.has_fieldtrip = exist('ft_freqanalysis', 'file') && exist('ft_preprocessing', 'file');
        deps.has_gretna = exist('gretna_sw_batch_networkanalysis_weight', 'file');

        if ~deps.has_fieldtrip
            warning('FieldTrip not found on path; rest.compute_all_features will fail at runtime until FieldTrip is added.');
        end
        if R.ComputeGraph && ~deps.has_gretna
            warning('GRETNA not found on path; graph measures will be skipped at runtime.');
        end

        state = state_update_history(state, op, state_strip_eeg_param(R), 'validated', deps);
        return;
    end

    local_maybe_add_deps(R);
    local_require_fieldtrip(R);

    EEG = state.EEG;
    out = struct();

    % ---- resolve output naming ----
    outDir = char(string(R.OutputPath));
    if isempty(outDir)
        outDir = local_cfg_fallback(state, {'Output','filepath'}, pwd);
    end
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    baseName = char(string(R.OutputBaseName));
    if isempty(baseName)
        baseName = local_cfg_fallback(state, {'Output','basename'}, '');
    end
    if isempty(baseName) && isfield(EEG, 'setname') && ~isempty(EEG.setname)
        baseName = char(string(EEG.setname));
    end
    if isempty(baseName)
        baseName = 'unnamed';
    end

    errorLog = fullfile(outDir, sprintf('%s_rest_features.error', baseName));
    log_step(state, meta, R.LogFile, sprintf('[rest.compute_all_features] BaseName=%s | OutputDir=%s', baseName, outDir));

    % ---- EEGLAB -> FieldTrip ----
    data = [];
    try
        data = eeglab_to_fieldtrip_epoched(EEG, R);
    catch ME
        log_step(state, meta, R.LogFile, sprintf('[rest.compute_all_features] ERROR converting EEG to FieldTrip: %s', ME.message));
        logPrint(errorLog, sprintf('EEGLAB->FieldTrip conversion error: %s', ME.message));
        error(ME.identifier, '%s', ME.message);
    end

    nTrial = numel(data.trial);
    out.nTrial = nTrial;
    if nTrial < R.MinTrials
        msg = sprintf('[rest.compute_all_features] Skipping: nTrial=%d < threshold=%d', nTrial, R.MinTrials);
        log_step(state, meta, R.LogFile, msg);
        state = state_update_history(state, op, state_strip_eeg_param(R), 'skipped', out);
        return;
    end

        % ---- 1) sensor space power + peak frequency ----
    res = struct();
    try
        log_step(state, meta, R.LogFile, '[rest.compute_all_features] Computing sensor power + peak frequency...');
        res.power = rest.compute_power(data, R);
        res.bandpower = rest.compute_bandpower(res.power, R);
        res.peakfrequency = rest.compute_peakfrequency(res.power, R);

        if isfield(R, 'RemoveAperiodic') && R.RemoveAperiodic
            log_step(state, meta, R.LogFile, '[rest.compute_all_features] Computing aperiodic (1/f) fit + flattened spectrum...');
            [res.aperiodic, res.power_osc] = rest.compute_aperiodic(res.power, R);
            res.peakfrequency_osc = rest.compute_peakfrequency(res.power_osc, R);
        end
    catch ME
        log_step(state, meta, R.LogFile, sprintf('[rest.compute_all_features] ERROR computing sensor features: %s', ME.message));
        logPrint(errorLog, sprintf('Sensor feature error: %s', ME.message));
        error(ME.identifier, '%s', ME.message);
    end

    % ---- 2) per-band source/connectivity/graph ----
    bands = fieldnames(R.FreqBand);
    out.bands_total = numel(bands);
    out.bands_ok = 0;

    if R.ComputeSource
        atlas = [];
        atlasPath = char(string(R.AtlasPath));
        if ~isempty(atlasPath)
            try
                atlas = rest.atlas_load(atlasPath, 'NetworkOrder', R.AtlasNetworkOrder);
            catch ME
                log_step(state, meta, R.LogFile, sprintf('[rest.compute_all_features] WARNING could not load atlas: %s', ME.message));
            end
        end

        for iB = 1:numel(bands)
            bandName = bands{iB};
            log_step(state, meta, R.LogFile, sprintf('[rest.compute_all_features] Band=%s', bandName));
            try
                source = rest.compute_spatial_filter(data, R, bandName);

                % Keep minimal source geometry even when KeepSource=false (for plotting/reporting).
                if isfield(source, 'pos') && isfield(source, 'inside') && ~isempty(source.pos) && ~isempty(source.inside)
                    res.(bandName).source_pos = source.pos(source.inside, :);
                    res.(bandName).source_inside_idx = find(source.inside);
                    if isfield(source, 'unit') && ~isempty(source.unit)
                        res.(bandName).source_unit = source.unit;
                    end
                end

                % Store parcellation metadata (ROI/network labels) for plotting/reordering.
                if isfield(res.(bandName), 'source_inside_idx') && ~isempty(res.(bandName).source_inside_idx)
                    try
                        idxInAtlas = res.(bandName).source_inside_idx;
                        if ~isempty(atlas) && isstruct(atlas) && isfield(atlas, 'pos') && ~isempty(atlas.pos)
                            idxMapped = local_map_sourcepos_to_atlas(R, res.(bandName), atlas);
                            if ~isempty(idxMapped)
                                idxInAtlas = idxMapped;
                            end
                        end
                        parc = rest.atlas_make_parcellation(atlas, idxInAtlas, ...
                            'Pos', res.(bandName).source_pos, ...
                            'NetworkOrder', R.AtlasNetworkOrder);
                        res.(bandName).parcellation = parc;
                    catch ME
                        log_step(state, meta, R.LogFile, sprintf('[rest.compute_all_features] WARNING parcellation failed (%s): %s', bandName, ME.message));
                    end
                end

                % Store source power (inside nodes) for source-space visualization.
                if R.ComputeSourcePower
                    try
                        pow = local_extract_source_pow(source);
                        if isempty(pow)
                            pow = rest.compute_source_power(data, source, R, bandName);
                        end
                        if ~isempty(pow)
                            res.(bandName).source_pow = pow(:);
                        end
                    catch ME
                        log_step(state, meta, R.LogFile, sprintf('[rest.compute_all_features] WARNING source power failed (%s): %s', bandName, ME.message));
                    end
                end

                if R.KeepSource
                    res.(bandName).source = source;
                end

                if R.ComputeDwpli
                    res.(bandName).dwpli_connMatrix = rest.compute_dwpli(data, source, R, bandName);
                end
                if R.ComputeAec
                    res.(bandName).aec_connMatrix = rest.compute_aec(data, source, R, bandName);
                end

                if R.ComputeGraph && exist('gretna_sw_batch_networkanalysis_weight', 'file')
                    if isfield(res.(bandName), 'dwpli_connMatrix')
                        [res.(bandName).dwpli_net_sum, res.(bandName).dwpli_node_sum] = ...
                            rest.compute_graph_measures(res.(bandName).dwpli_connMatrix, R);
                    end
                    if isfield(res.(bandName), 'aec_connMatrix')
                        [res.(bandName).aec_net_sum, res.(bandName).aec_node_sum] = ...
                            rest.compute_graph_measures(res.(bandName).aec_connMatrix, R);
                    end
                elseif R.ComputeGraph
                    log_step(state, meta, R.LogFile, '[rest.compute_all_features] GRETNA not found; skipping graph measures.');
                end

                out.bands_ok = out.bands_ok + 1;
            catch ME
                log_step(state, meta, R.LogFile, sprintf('[rest.compute_all_features] WARNING band=%s failed: %s', bandName, ME.message));
                logPrint(errorLog, sprintf('Band %s error: %s', bandName, ME.message));
                continue;
            end
        end
    else
        log_step(state, meta, R.LogFile, '[rest.compute_all_features] ComputeSource=OFF (skipping source/connectivity/graph).');
    end

    paramSnap = state_strip_eeg_param(R);
    % Avoid bloating outputs with large structs (headmodel/elec).
    if isfield(paramSnap, 'HeadModel'), paramSnap.HeadModel = []; end
    if isfield(paramSnap, 'Elec'),      paramSnap.Elec = []; end
    res.params = paramSnap;
    res.nTrial = nTrial;
    res.subid = string(baseName);

    % ---- save ----
    if R.SaveMat
        outFile = fullfile(outDir, sprintf('%s_rest_features.mat', baseName));
        try
            save(outFile, 'res', '-v7.3');
            if ~isfield(state, 'rest') || ~isstruct(state.rest)
                state.rest = struct();
            end
            state.rest.output_file = outFile;
        catch ME
            log_step(state, meta, R.LogFile, sprintf('[rest.compute_all_features] ERROR saving: %s', ME.message));
            logPrint(errorLog, sprintf('Save error: %s', ME.message));
            error(ME.identifier, '%s', ME.message);
        end
    end

    if R.KeepInState
        if ~isfield(state, 'rest') || ~isstruct(state.rest)
            state.rest = struct();
        end
        state.rest.features = res;
    end

    state = state_update_history(state, op, state_strip_eeg_param(R), 'success', out);
end

% ----------------- helpers -----------------
function local_maybe_add_deps(R)
    if ~isfield(R, 'AutoAddDeps') || ~R.AutoAddDeps
        return;
    end

    if ~exist('ft_freqanalysis', 'file') || ~exist('ft_preprocessing', 'file')
        ftRoot = char(string(R.FieldTripRoot));
        if isempty(ftRoot)
            ftRoot = getenv('FIELDTRIP_ROOT');
        end
        if ~isempty(ftRoot) && isfolder(ftRoot)
            addpath(ftRoot);
            if exist('ft_defaults', 'file')
                try, ft_defaults; catch, end %#ok<CTCH>
            end
        end
    end

    if isfield(R, 'ComputeGraph') && R.ComputeGraph && ~exist('gretna_sw_batch_networkanalysis_weight', 'file')
        grRoot = char(string(R.GretnaRoot));
        if isempty(grRoot)
            grRoot = getenv('GRETNA_ROOT');
        end
        if ~isempty(grRoot) && isfolder(grRoot)
            addpath(genpath(grRoot));
        end
    end
end

function local_require_fieldtrip(R)
    if ~exist('ft_freqanalysis', 'file') || ~exist('ft_preprocessing', 'file')
        ftRoot = '';
        if nargin >= 1 && isfield(R, 'FieldTripRoot')
            ftRoot = char(string(R.FieldTripRoot));
        end
        envRoot = getenv('FIELDTRIP_ROOT');
        hint = 'Add FieldTrip to your MATLAB path.';
        if ~isempty(ftRoot)
            hint = sprintf('Set FieldTripRoot=\"%s\" (or add it to path) and rerun.', ftRoot);
        elseif ~isempty(envRoot)
            hint = sprintf('Setenv FIELDTRIP_ROOT=\"%s\" (or add it to path) and rerun.', envRoot);
        end
        error('rest:MissingDependency:FieldTrip', 'FieldTrip not found on path (missing ft_* functions). %s', hint);
    end

    if exist('ft_defaults', 'file')
        try, ft_defaults; catch, end %#ok<CTCH>
    end
end

function v = local_cfg_fallback(state, path, default)
    v = default;
    if nargin < 3, default = []; end
    if ~isstruct(state) || ~isfield(state, 'cfg') || ~isstruct(state.cfg)
        return;
    end
    t = state.cfg;
    for i = 1:numel(path)
        f = path{i};
        if ~isstruct(t) || ~isfield(t, f)
            return;
        end
        t = t.(f);
    end
    v = t;
    if isstring(v), v = char(v); end
end

function data = eeglab_to_fieldtrip_epoched(EEG, R)
    % Minimal EEGLAB->FieldTrip conversion for epoched EEG.
    if ~isfield(EEG, 'data') || isempty(EEG.data)
        error('rest:BadEEG', 'EEG.data is empty.');
    end
    if ~isfield(EEG, 'trials') || EEG.trials < 1
        error('rest:BadEEG', 'EEG.trials is invalid.');
    end

    labels = {EEG.chanlocs.labels};
    labels = labels(:);

    if isfield(EEG, 'times') && ~isempty(EEG.times)
        tvec = double(EEG.times(:).') / 1000;
    else
        t0 = 0;
        if isfield(EEG, 'xmin') && ~isempty(EEG.xmin)
            t0 = double(EEG.xmin);
        end
        tvec = t0 + (0:(EEG.pnts-1)) / double(EEG.srate);
    end

    nTr = EEG.trials;
    data = struct();
    data.label = labels;
    data.fsample = double(EEG.srate);
    data.trial = cell(1, nTr);
    data.time = cell(1, nTr);
    data.sampleinfo = zeros(nTr, 2);
    for t = 1:nTr
        if nTr == 1
            X = EEG.data;
        else
            X = EEG.data(:, :, t);
        end
        data.trial{t} = double(X);
        data.time{t} = tvec;
        data.sampleinfo(t, :) = [1 size(data.trial{t}, 2)];
    end

    data = local_attach_elec(data, EEG, R);
end

function data = local_attach_elec(data, EEG, R)
    % Attach sensor positions if provided.
    unit = char(string(R.Unit));

    if ~isempty(R.Elec)
        elec = R.Elec;
        data = local_align_elec(data, elec, unit);
        return;
    end

    tmplFile = char(string(R.TemplateElecFile));
    if ~isempty(tmplFile)
        if ~exist('ft_read_sens', 'file')
            error('rest:MissingDependency:FieldTrip', 'FieldTrip not found (missing ft_read_sens).');
        end
        elecT = ft_read_sens(tmplFile);
        data = local_align_elec(data, elecT, unit);
        return;
    end

    % Fall back to EEGLAB chanlocs XYZ if available (coord system/units may be unknown).
    try
        if isfield(EEG, 'chanlocs') && ~isempty(EEG.chanlocs) && isfield(EEG.chanlocs, 'X')
            X = [EEG.chanlocs.X]'; Y = [EEG.chanlocs.Y]'; Z = [EEG.chanlocs.Z]';
            if all(isfinite(X)) && all(isfinite(Y)) && all(isfinite(Z)) && any([X;Y;Z] ~= 0)
                elec = struct();
                elec.label = data.label;
                elec.chanpos = [X Y Z];
                elec.elecpos = [X Y Z];
                elec.unit = unit;
                elec.type = 'eeglab';
                data.elec = elec;
            end
        end
    catch
        % best-effort only
    end
end

function data = local_align_elec(data, elec, unit)
    if ~isfield(elec, 'label') || isempty(elec.label)
        error('rest:BadElec', 'Elec struct missing label.');
    end

    % Ensure both are cellstr
    dlab = cellstr(string(data.label));
    elab = cellstr(string(elec.label));

    [common, iData, iElec] = intersect(dlab, elab, 'stable');
    if isempty(common)
        error('rest:BadElec', 'No overlapping channel labels between data and elec template.');
    end
    if numel(common) < numel(dlab)
        missing = setdiff(dlab, common, 'stable');
        warning('Dropping %d channels missing from electrode template: %s', numel(missing), strjoin(missing, ', '));

        % drop channels from data (trial matrices + labels)
        data.label = data.label(iData);
        for t = 1:numel(data.trial)
            data.trial{t} = data.trial{t}(iData, :);
        end
    end

    % Subset/reorder electrode struct to match data.label ordering.
    elec2 = elec;
    elec2.label = elec.label(iElec);
    if isfield(elec2, 'chanpos'), elec2.chanpos = elec.chanpos(iElec, :); end
    if isfield(elec2, 'elecpos'), elec2.elecpos = elec.elecpos(iElec, :); end
    if isfield(elec2, 'chantype'), elec2.chantype = elec.chantype(iElec, :); end
    if isfield(elec2, 'chanunit'), elec2.chanunit = elec.chanunit(iElec, :); end

    if exist('ft_convert_units', 'file')
        try
            elec2 = ft_convert_units(elec2, unit);
        catch
        end
    end

    data.elec = elec2;
end

function powInside = local_extract_source_pow(source)
    powInside = [];
    if ~isstruct(source) || ~isfield(source, 'inside') || isempty(source.inside)
        return;
    end
    inside = logical(source.inside(:));
    n = numel(inside);

    powAll = [];
    if isfield(source, 'pow') && isnumeric(source.pow)
        powAll = source.pow;
    elseif isfield(source, 'avg') && isstruct(source.avg) && isfield(source.avg, 'pow') && isnumeric(source.avg.pow)
        powAll = source.avg.pow;
    end

    if isempty(powAll)
        return;
    end

    % Accept [n x 1] or [1 x n].
    if isvector(powAll) && numel(powAll) == n
        powInside = double(powAll(:));
        powInside = powInside(inside);
    end
end

function idxInsideAtlas = local_map_sourcepos_to_atlas(R, bandRes, atlas)
    idxInsideAtlas = [];
    if ~isstruct(bandRes) || ~isfield(bandRes, 'source_inside_idx') || isempty(bandRes.source_inside_idx)
        return;
    end
    if ~isstruct(atlas) || ~isfield(atlas, 'pos') || isempty(atlas.pos)
        return;
    end

    idxInside = bandRes.source_inside_idx(:);
    atlasPos = double(atlas.pos);

    % Preferred path: map provided SourcePos (all nodes) to atlas rows, then
    % apply inside indices. This preserves non-contiguous atlas subset order.
    if isfield(R, 'SourcePos') && ~isempty(R.SourcePos)
        srcPosAll = double(R.SourcePos);
        idxAll = local_nearest_row_map(srcPosAll, atlasPos);
        if numel(idxAll) >= max(idxInside) && all(isfinite(idxAll(idxInside)))
            idxInsideAtlas = idxAll(idxInside);
            return;
        end
    end

    % Fallback: map inside positions directly.
    if isfield(bandRes, 'source_pos') && ~isempty(bandRes.source_pos)
        idxDirect = local_nearest_row_map(double(bandRes.source_pos), atlasPos);
        if all(isfinite(idxDirect))
            idxInsideAtlas = idxDirect;
            return;
        end
    end
end

function idxMap = local_nearest_row_map(pos, atlasPos)
    n = size(pos, 1);
    idxMap = nan(n, 1);
    if n == 0 || isempty(atlasPos)
        return;
    end

    % Coordinates are expected in mm; use a small tolerance for numeric drift.
    tolMm = 1e-3;
    tol2 = tolMm * tolMm;
    for i = 1:n
        d2 = sum((atlasPos - pos(i, :)).^2, 2);
        [dMin, k] = min(d2);
        if ~isempty(k) && isfinite(dMin) && dMin <= tol2
            idxMap(i) = k;
        end
    end
end
    
