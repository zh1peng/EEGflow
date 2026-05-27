function state = check_headmodel(state, args, meta)
%CHECK_HEADMODEL Check and optionally realign EEG electrodes to a headmodel.
%
% This state-based step prepares source-analysis geometry before
% rest.compute_all_features. It loads/converts the headmodel and electrode
% definition, optionally realigns electrodes with FieldTrip, computes simple
% geometry QC metrics, and stores the checked geometry in:
%   state.source.geometry.headmodel
%   state.source.geometry.elec
%   state.source.geometry.qc
%
% RealignMethod:
%   'none'      : only unit conversion, label matching, and QC
%   'project'   : project electrodes onto the scalp/headshape surface
%   'headshape' : fit electrodes to a headshape with cfg.warp
%   'template'  : fit electrodes to RealignTarget with cfg.warp
%   'fiducial'  : rigid realign with FiducialTarget/FiducialLabels
%   'interactive': manually adjust electrodes in the FieldTrip GUI

    if nargin < 1 || isempty(state), state = struct(); end
    if nargin < 2 || isempty(args),  args = struct();  end
    if nargin < 3 || isempty(meta),  meta = struct();  end

    op = 'check_headmodel';
    cfg0 = state_get_config(state, op);
    params = state_merge(cfg0, args);

    p = inputParser;
    p.addParameter('LogFile', '', @(s) ischar(s) || isstring(s));
    p.addParameter('OutputPath', '', @(s) ischar(s) || isstring(s));
    p.addParameter('OutputBaseName', '', @(s) ischar(s) || isstring(s));
    p.addParameter('SaveMat', false, @(x) islogical(x) && isscalar(x));
    p.addParameter('KeepInState', true, @(x) islogical(x) && isscalar(x));

    p.addParameter('HeadModelPath', '', @(s) ischar(s) || isstring(s));
    p.addParameter('HeadModelTemplate', '', @(s) ischar(s) || isstring(s));
    p.addParameter('HeadModel', [], @(x) isempty(x) || isstruct(x));
    p.addParameter('ElectrodePath', '', @(s) ischar(s) || isstring(s));
    p.addParameter('ElectrodeTemplate', '', @(s) ischar(s) || isstring(s));
    p.addParameter('TemplateElecFile', '', @(s) ischar(s) || isstring(s));
    p.addParameter('Elec', [], @(x) isempty(x) || isstruct(x));
    p.addParameter('Unit', 'mm', @(s) ischar(s) || isstring(s));

    p.addParameter('RealignMethod', 'none', @(s) ischar(s) || isstring(s));
    p.addParameter('Warp', 'rigidbody', @(s) ischar(s) || isstring(s));
    p.addParameter('RealignFeedback', 'no', @(s) ischar(s) || isstring(s));
    p.addParameter('RealignTarget', [], @(x) isempty(x) || isstruct(x) || ischar(x) || isstring(x) || iscell(x));
    p.addParameter('FiducialTarget', [], @(x) isempty(x) || isstruct(x));
    p.addParameter('FiducialLabels', {'NAS','LPA','RPA'}, @(x) iscellstr(x) || isstring(x));
    p.addParameter('Headshape', [], @(x) isempty(x) || isstruct(x) || isnumeric(x));
    p.addParameter('HeadshapePath', '', @(s) ischar(s) || isstring(s));
    p.addParameter('ScalpIndex', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 1));

    p.addParameter('MinMatchedChannels', 16, @(x) isnumeric(x) && isscalar(x) && x >= 1);
    p.addParameter('MaxMedianSurfaceDistance', 15, @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 0));
    p.addParameter('MaxP95SurfaceDistance', 35, @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 0));
    p.addParameter('FailOnQC', true, @(x) islogical(x) && isscalar(x));
    p.addParameter('ReviewRequired', true, @(x) islogical(x) && isscalar(x));

    p.addParameter('PlotQC', false, @(x) islogical(x) && isscalar(x));
    p.addParameter('FigurePath', '', @(s) ischar(s) || isstring(s));

    nv = state_struct2nv(params);
    p.parse(nv{:});
    R = p.Results;
    R.RealignMethod = lower(char(string(R.RealignMethod)));
    R.Unit = char(string(R.Unit));

    if isfield(meta, 'validate_only') && meta.validate_only
        state = state_update_history(state, op, local_strip_geometry_param(R), 'validated', struct());
        return;
    end

    local_require_fieldtrip();
    state_require_eeg(state, op);

    log_step(state, meta, R.LogFile, sprintf('[source.check_headmodel] Loading geometry | method=%s | unit=%s', R.RealignMethod, R.Unit));

    headmodel = load_headmodel(R, R.Unit);
    elec = local_load_elec(state.EEG, R);
    elec = local_convert_units(elec, R.Unit);
    [elec, labelQc] = local_match_elec_to_eeg(elec, state.EEG);

    headshape = local_resolve_headshape(headmodel, R);

    qcBefore = local_geometry_qc(headmodel, elec, headshape, R, labelQc);
    elecAligned = elec;

    if ~strcmp(R.RealignMethod, 'none')
        elecAligned = local_realign_elec(elec, headshape, R);
        elecAligned = local_convert_units(elecAligned, R.Unit);
    end

    qcAfter = local_geometry_qc(headmodel, elecAligned, headshape, R, labelQc);
    qcAfter.method = R.RealignMethod;
    qcAfter.before = qcBefore;
    qcAfter.pass = local_qc_pass(qcAfter, R);
    qcAfter.review_required = R.ReviewRequired;

    if qcAfter.pass
        log_step(state, meta, R.LogFile, sprintf('[source.check_headmodel] QC PASS | matched=%d | medianDist=%.2f | p95Dist=%.2f', ...
            qcAfter.nMatchedChannels, qcAfter.surfaceDistanceMedian, qcAfter.surfaceDistanceP95));
    else
        msg = sprintf('[source.check_headmodel] QC FAIL | matched=%d | medianDist=%.2f | p95Dist=%.2f', ...
            qcAfter.nMatchedChannels, qcAfter.surfaceDistanceMedian, qcAfter.surfaceDistanceP95);
        log_step(state, meta, R.LogFile, msg);
        if R.FailOnQC
            error('source:check_headmodel:QCFailed', '%s', msg);
        end
    end

    out = struct();
    out.qc = qcAfter;
    out.unit = R.Unit;

    if R.KeepInState
        if ~isfield(state, 'source') || ~isstruct(state.source)
            state.source = struct();
        end
        state.source.geometry = struct();
        state.source.geometry.headmodel = headmodel;
        state.source.geometry.elec = elecAligned;
        state.source.geometry.qc = qcAfter;
        state.source.geometry.unit = R.Unit;
        if ~isfield(state.source, 'qc') || ~isstruct(state.source.qc)
            state.source.qc = struct();
        end
        state.source.qc.geometry = qcAfter;
    end

    if R.SaveMat
        outDir = char(string(R.OutputPath));
        if isempty(outDir)
            outDir = local_cfg_fallback(state, {'Output','filepath'}, pwd);
        end
        if ~exist(outDir, 'dir'), mkdir(outDir); end
        baseName = char(string(R.OutputBaseName));
        if isempty(baseName) && isfield(state.EEG, 'setname') && ~isempty(state.EEG.setname)
            baseName = char(string(state.EEG.setname));
        end
        if isempty(baseName), baseName = 'unnamed'; end
        outFile = fullfile(outDir, sprintf('%s_headmodel_qc.mat', baseName));
        qc = qcAfter; %#ok<NASGU>
        save(outFile, 'qc', '-v7.3');
        out.output_file = outFile;
    end

    if R.PlotQC
        figPath = char(string(R.FigurePath));
        if isempty(figPath)
            figPath = local_default_figure_path(state, R);
        end
        local_plot_qc(headshape, elecAligned, figPath);
        out.figure_file = figPath;
    end

    if R.ReviewRequired
        if isfield(out, 'figure_file')
            log_step(state, meta, R.LogFile, sprintf('[source.check_headmodel] REVIEW REQUIRED: inspect %s', out.figure_file));
        else
            log_step(state, meta, R.LogFile, '[source.check_headmodel] REVIEW REQUIRED: inspect geometry visually or run with PlotQC=true.');
        end
    end

    state = state_update_history(state, op, local_strip_geometry_param(R), 'success', out);
end

function local_require_fieldtrip()
    if exist('ft_convert_units', 'file') ~= 2 || exist('ft_read_sens', 'file') ~= 2
        error('source:check_headmodel:MissingFieldTrip', 'FieldTrip is required for headmodel/electrode checks.');
    end
end

function elec = local_load_elec(EEG, R)
    if ~isempty(R.Elec)
        elec = R.Elec;
        return;
    end

    tmplFile = char(string(R.ElectrodePath));
    if isempty(tmplFile)
        tmplFile = char(string(R.TemplateElecFile));
    end
    if isempty(tmplFile) && ~isempty(char(string(R.ElectrodeTemplate)))
        tmplFile = source.electrode_default_path(R.ElectrodeTemplate);
    end
    if ~isempty(tmplFile)
        if exist(tmplFile, 'file') ~= 2
            error('source:check_headmodel:ElecNotFound', 'TemplateElecFile not found: %s', tmplFile);
        end
        elec = ft_read_sens(tmplFile);
        return;
    end

    if isfield(EEG, 'chanlocs') && ~isempty(EEG.chanlocs) && isfield(EEG.chanlocs, 'X')
        labels = {EEG.chanlocs.labels}';
        X = [EEG.chanlocs.X]'; Y = [EEG.chanlocs.Y]'; Z = [EEG.chanlocs.Z]';
        if all(isfinite(X)) && all(isfinite(Y)) && all(isfinite(Z)) && any([X; Y; Z] ~= 0)
            elec = struct();
            elec.label = labels;
            elec.chanpos = [X Y Z];
            elec.elecpos = elec.chanpos;
            elec.unit = R.Unit;
            elec.type = 'eeglab';
            return;
        end
    end

    error('source:check_headmodel:MissingElec', ...
        'Provide Elec, ElectrodePath, ElectrodeTemplate, TemplateElecFile, or EEG.chanlocs with XYZ coordinates.');
end

function elec = local_convert_units(elec, unit)
    if exist('ft_convert_units', 'file') == 2 && ~isempty(unit)
        elec = ft_convert_units(elec, unit);
    end
end

function [elec2, qc] = local_match_elec_to_eeg(elec, EEG)
    qc = struct();
    dlab = cellstr(string({EEG.chanlocs.labels}));
    elab = cellstr(string(elec.label));
    [common, iData, iElec] = intersect(dlab(:), elab(:), 'stable');

    qc.nEegChannels = numel(dlab);
    qc.nElecChannels = numel(elab);
    qc.nMatchedChannels = numel(common);
    qc.matchedLabels = common(:);
    qc.missingInElec = setdiff(dlab(:), common(:), 'stable');
    qc.extraInElec = setdiff(elab(:), common(:), 'stable');
    qc.eegIndex = iData(:);

    if isempty(common)
        error('source:check_headmodel:NoChannelOverlap', 'No overlapping labels between EEG channels and electrode definition.');
    end

    elec2 = elec;
    elec2.label = elec.label(iElec);
    if isfield(elec, 'chanpos'), elec2.chanpos = elec.chanpos(iElec, :); end
    if isfield(elec, 'elecpos'), elec2.elecpos = elec.elecpos(iElec, :); end
    if isfield(elec, 'chantype'), elec2.chantype = elec.chantype(iElec, :); end
    if isfield(elec, 'chanunit'), elec2.chanunit = elec.chanunit(iElec, :); end
end

function headshape = local_resolve_headshape(headmodel, R)
    headshape = [];
    if ~isempty(R.Headshape)
        headshape = R.Headshape;
    elseif ~isempty(char(string(R.HeadshapePath)))
        headshape = ft_read_headshape(char(string(R.HeadshapePath)));
    elseif isfield(headmodel, 'bnd') && ~isempty(headmodel.bnd)
        idx = local_scalp_index(headmodel, R);
        headshape = headmodel.bnd(idx);
    elseif isfield(headmodel, 'pos') && ~isempty(headmodel.pos)
        headshape = struct('pos', headmodel.pos);
    end

    if isempty(headshape)
        return;
    end
    if isnumeric(headshape)
        headshape = struct('pos', double(headshape));
    end
    if exist('ft_convert_units', 'file') == 2 && isstruct(headshape) && isfield(headshape, 'pos')
        try, headshape = ft_convert_units(headshape, R.Unit); catch, end %#ok<CTCH>
    end
end

function idx = local_scalp_index(headmodel, R)
    if ~isempty(R.ScalpIndex)
        idx = round(R.ScalpIndex);
        return;
    end
    bnd = headmodel.bnd;
    score = nan(numel(bnd), 1);
    for i = 1:numel(bnd)
        if isfield(bnd(i), 'pos') && ~isempty(bnd(i).pos)
            pos = double(bnd(i).pos);
            ctr = median(pos, 1, 'omitnan');
            score(i) = median(sqrt(sum((pos - ctr).^2, 2)), 'omitnan');
        end
    end
    [~, idx] = max(score);
    if isempty(idx) || ~isfinite(score(idx))
        idx = 1;
    end
end

function elec2 = local_realign_elec(elec, headshape, R)
    if exist('ft_electroderealign', 'file') ~= 2
        error('source:check_headmodel:MissingFieldTrip', 'ft_electroderealign is required for RealignMethod=%s.', R.RealignMethod);
    end

    cfg = [];
    cfg.method = R.RealignMethod;
    cfg.feedback = char(string(R.RealignFeedback));

    switch R.RealignMethod
        case {'project','headshape'}
            if isempty(headshape)
                error('source:check_headmodel:MissingHeadshape', 'RealignMethod=%s requires a headshape/scalp surface.', R.RealignMethod);
            end
            cfg.headshape = headshape;
            if strcmp(R.RealignMethod, 'headshape')
                cfg.warp = char(string(R.Warp));
            end
        case 'template'
            if isempty(R.RealignTarget)
                error('source:check_headmodel:MissingTarget', 'RealignMethod=template requires RealignTarget.');
            end
            cfg.target = R.RealignTarget;
            cfg.warp = char(string(R.Warp));
        case 'fiducial'
            if isempty(R.FiducialTarget)
                error('source:check_headmodel:MissingTarget', 'RealignMethod=fiducial requires FiducialTarget.');
            end
            cfg.target = R.FiducialTarget;
            cfg.fiducial = cellstr(string(R.FiducialLabels));
        case 'interactive'
            if ~isempty(headshape)
                cfg.headshape = headshape;
            end
        otherwise
            error('source:check_headmodel:BadRealignMethod', ...
                'RealignMethod must be none|project|headshape|template|fiducial|interactive.');
    end

    elec2 = ft_electroderealign(cfg, elec);
end

function figPath = local_default_figure_path(state, R)
    outDir = char(string(R.OutputPath));
    if isempty(outDir)
        outDir = local_cfg_fallback(state, {'Output','filepath'}, pwd);
    end
    baseName = char(string(R.OutputBaseName));
    if isempty(baseName) && isfield(state, 'EEG') && isstruct(state.EEG) && ...
            isfield(state.EEG, 'setname') && ~isempty(state.EEG.setname)
        baseName = char(string(state.EEG.setname));
    end
    if isempty(baseName), baseName = 'unnamed'; end
    figPath = fullfile(outDir, sprintf('%s_headmodel_qc.png', baseName));
end

function qc = local_geometry_qc(headmodel, elec, headshape, R, labelQc)
    qc = labelQc;
    qc.unit = R.Unit;
    qc.headmodelType = local_get_field(headmodel, 'type', 'unknown');
    qc.elecExtent = local_extent(local_elec_pos(elec));

    hsPos = local_headshape_pos(headshape);
    qc.headshapeExtent = local_extent(hsPos);
    qc.scaleRatioElecToHeadshape = qc.elecExtent.medianRadius / qc.headshapeExtent.medianRadius;

    qc.surfaceDistanceMedian = NaN;
    qc.surfaceDistanceP95 = NaN;
    qc.surfaceDistanceMax = NaN;
    if ~isempty(hsPos)
        d = local_nearest_dist(local_elec_pos(elec), hsPos);
        qc.surfaceDistanceMedian = median(d, 'omitnan');
        qc.surfaceDistanceP95 = prctile(d, 95);
        qc.surfaceDistanceMax = max(d, [], 'omitnan');
    end
end

function pass = local_qc_pass(qc, R)
    pass = qc.nMatchedChannels >= R.MinMatchedChannels;
    if ~isempty(R.MaxMedianSurfaceDistance) && isfinite(qc.surfaceDistanceMedian)
        pass = pass && qc.surfaceDistanceMedian <= R.MaxMedianSurfaceDistance;
    end
    if ~isempty(R.MaxP95SurfaceDistance) && isfinite(qc.surfaceDistanceP95)
        pass = pass && qc.surfaceDistanceP95 <= R.MaxP95SurfaceDistance;
    end
end

function pos = local_elec_pos(elec)
    if isfield(elec, 'chanpos') && ~isempty(elec.chanpos)
        pos = double(elec.chanpos);
    elseif isfield(elec, 'elecpos') && ~isempty(elec.elecpos)
        pos = double(elec.elecpos);
    else
        pos = [];
    end
end

function pos = local_headshape_pos(headshape)
    pos = [];
    if isstruct(headshape) && isfield(headshape, 'pos') && ~isempty(headshape.pos)
        pos = double(headshape.pos);
    elseif isnumeric(headshape) && size(headshape, 2) == 3
        pos = double(headshape);
    end
end

function e = local_extent(pos)
    e = struct('medianRadius', NaN, 'maxRadius', NaN);
    if isempty(pos)
        return;
    end
    ctr = median(pos, 1, 'omitnan');
    r = sqrt(sum((pos - ctr).^2, 2));
    e.medianRadius = median(r, 'omitnan');
    e.maxRadius = max(r, [], 'omitnan');
end

function d = local_nearest_dist(pos, ref)
    if isempty(pos) || isempty(ref)
        d = [];
        return;
    end
    n = size(pos, 1);
    d = nan(n, 1);
    chunk = 2000;
    for i = 1:n
        best = inf;
        for j = 1:chunk:size(ref, 1)
            jj = j:min(j + chunk - 1, size(ref, 1));
            dd = sum((ref(jj, :) - pos(i, :)).^2, 2);
            best = min(best, min(dd));
        end
        d(i) = sqrt(best);
    end
end

function v = local_get_field(s, f, default)
    v = default;
    if isstruct(s) && isfield(s, f) && ~isempty(s.(f))
        v = s.(f);
    end
end

function v = local_cfg_fallback(state, path, default)
    v = default;
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

function local_plot_qc(headshape, elec, figPath)
    pos = local_headshape_pos(headshape);
    ep = local_elec_pos(elec);
    fig = figure('Visible', 'off', 'Color', 'w');
    hold on;
    if isstruct(headshape) && isfield(headshape, 'tri') && ~isempty(headshape.tri)
        patch('Vertices', headshape.pos, 'Faces', headshape.tri, ...
            'FaceColor', [0.85 0.85 0.85], 'EdgeColor', 'none', 'FaceAlpha', 0.18);
    elseif ~isempty(pos)
        plot3(pos(:,1), pos(:,2), pos(:,3), '.', 'Color', [0.85 0.85 0.85], 'MarkerSize', 2);
    end
    scatter3(ep(:,1), ep(:,2), ep(:,3), 28, 'filled', 'MarkerFaceColor', [0.1 0.35 0.85]);
    axis equal vis3d;
    grid on;
    xlabel('X'); ylabel('Y'); zlabel('Z');
    title('Headmodel / electrode QC');
    view(135, 25);
    camlight headlight;
    lighting gouraud;
    [figDir, ~, ~] = fileparts(figPath);
    if ~isempty(figDir) && ~isfolder(figDir), mkdir(figDir); end
    exportgraphics(fig, figPath, 'Resolution', 150);
    close(fig);
end

function params = local_strip_geometry_param(params)
    params = state_strip_eeg_param(params);
    bigFields = {'HeadModel','Elec','Headshape','RealignTarget','FiducialTarget'};
    for i = 1:numel(bigFields)
        f = bigFields{i};
        if isfield(params, f)
            params.(f) = [];
        end
    end
end

