function out = run_cp(Out, varargin)
% RUN_CP  CP decomposition on an EEG tensor [channels x time x subjects]
%   This function takes the output of movie.collect_segments and performs
%   a CP tensor decomposition.
%
% Requires: Tensor Toolbox (Kolda & Bader)
%
% Inputs:
%   Out     - The output struct from movie.collect_segments (REQUIRED).
%
% Name-Value Pair Inputs:
%   'Rank'              (numeric, default: 3) The number of components.
%   'ZscoreAcrossTime'  (logical, default: true) Z-score each channel's time course.
%   'DemeanAcrossTime'  (logical, default: false) Demean each channel's time course.
%   'WhitenTimePCA'     (false or numeric, default: false) Number of components for PCA whitening.
%   'SubjectPrefix'     (char, default: 'sub_') The prefix of subject fields in the Out struct.
%   'Plot'              (logical, default: true) Whether to automatically plot the results.
%
% Example:
%   % 1. First, extract movie data segments for all subjects
%   Out = movie.collect_segments( ...
%       'study_path', 'Z:\path\to\your\data', ...
%       'StartMarker', 'movie_start', ...
%       'EndMarker', 'movie_end', ...
%       'chan_exclude', {'EOG', 'HEOG', 'VEOG'});
% 
%   % 2. Then, run the CP decomposition on the extracted data
%   cp_results = movie.run_cp(Out, ...
%       'Rank', 15, ...
%       'WhitenTimePCA', 30);
% 
% Output (struct 'out'):

%   .T        - The tensor object [C x T x S] used for decomposition.
%   .cp       - The ktensor result from cp_als.
%   .A, .B, .C- Factor matrices for [channels, time, subjects].
%   .chanlocs - Channel locations from Out.meta.
%   .fs    - Sampling rate from Out.meta.
%   .tvec     - Time vector for the common segment length.
%   .subjects - List of subject identifiers used in the decomposition.

%% ----------------------------
% 0) Defaults & Input Validation
% ----------------------------
p = inputParser;
p.FunctionName = 'run_cp';
addRequired(p, 'Out', @(x) isstruct(x) && isfield(x, 'meta'));
addParameter(p, 'Rank', 3, @isnumeric);
addParameter(p, 'ZscoreAcrossTime', true, @islogical);
addParameter(p, 'DemeanAcrossTime', false, @islogical);
addParameter(p, 'WhitenTimePCA', false);
addParameter(p, 'SubjectPrefix', 'sub_', @ischar);
addParameter(p, 'Plot', true, @islogical);

parse(p, Out, varargin{:});
params = p.Results;

fprintf('CP rank = %d\n', params.Rank);

%% ----------------------------
% 1) Extract Data and Pre-process
% -----------------------------
fnames = fieldnames(Out);
sub_idx = startsWith(fnames, params.SubjectPrefix);
subjects = fnames(sub_idx);
S = numel(subjects);

assert(S > 0, 'No subject data found in the input struct.');

% Check data dimensionality from first subject
is_tfr = isfield(Out.meta, 'tfr') && Out.meta.tfr.enable;

raw_data = cell(1, S);
fprintf('Processing %d subjects...\n', S);

for s = 1:S
    subKey = subjects{s};
    X = double(Out.(subKey).data);

    % (Optional) Per-subject, per-channel normalization
    if params.DemeanAcrossTime
        X = X - mean(X, ndims(X));
    end
    if params.ZscoreAcrossTime
        mu = mean(X, ndims(X));
        sd = std(X, 0, ndims(X));
        sd(sd == 0) = 1;
        X = (X - mu) ./ sd;
    end

    raw_data{s} = X;
end

%% ----------------------------
% 2) Align Dimensions & Build Tensor
% -----------------------------
srate = Out.meta.fs;

if is_tfr
    % ---- TFR Data: Reshape to [channel, freq*time, subject]
    fprintf('Data is TFR. Reshaping to [chan, freq*time, subject]');
    freq_lens = cellfun(@(x) size(x, 2), raw_data);
    time_lens = cellfun(@(x) size(x, 3), raw_data);
    minF = min(freq_lens);
    minT = min(time_lens);
    C = size(raw_data{1}, 1);

    fvec = Out.meta.tfr_freqs;
    tvec = Out.meta.tfr_times;
    if numel(fvec) > minF, fvec = fvec(1:minF); end
    if numel(tvec) > minT, tvec = tvec(1:minT); end

    fprintf('Common freq length = %d, time length = %d', minF, minT);
    
    new_dim_len = minF * minT;
    X3 = zeros(C, new_dim_len, S, 'double');
    for s = 1:S
        % Crop to common size
        data_cropped = raw_data{s}(:, 1:minF, 1:minT);
        % Reshape
        X3(:, :, s) = reshape(data_cropped, C, new_dim_len);
    end
    T = tensor(X3);
    clear X3;

else
    % ---- 3D Tensor: [channel, time, subject]
    fprintf('Data is 3D (Time-series)');
    time_lens = cellfun(@(x) size(x, 2), raw_data);
    minT = min(time_lens);
    C = size(raw_data{1}, 1);

    fprintf('Common time length = %d samples (%.2f s at %g Hz)', ...
        minT, minT / srate, srate);

    X3 = zeros(C, minT, S, 'double');
    for s = 1:S
        X3(:, :, s) = raw_data{s}(:, 1:minT);
    end
    tvec = (0:minT - 1) / srate;
    T = tensor(X3);
    clear X3;
end


%% ----------------------------
% 3) (Optional) Time Whitening via PCA
% -----------------------------
if ~is_tfr && isnumeric(params.WhitenTimePCA) && params.WhitenTimePCA > 0
    Rt = params.WhitenTimePCA; % # temporal comps to keep
    fprintf('Temporal PCA whitening to %d comps...\n', Rt);

    X3 = double(T);
    % Stack subjects along time for PCA fit
    Xt = reshape(permute(X3, [2 1 3]), minT, []); % [T x (C*S)]

    % Economy SVD
    [Ut, St, ~] = svd(Xt, 'econ');
    Rt = min(Rt, size(Ut, 2));
    Wt = Ut(:, 1:Rt); % [T x Rt]

    % Project each subject’s [C x T]
    X3w = zeros(C, Rt, S);
    for s = 1:S
        X3w(:, :, s) = (X3(:, :, s) * Wt); % [C x Rt]
    end
    T = tensor(X3w); % Overwrite
    minT = Rt;
    tvec = (1:Rt); % Abstract temporal components (no longer seconds)
    clear Xt Ut St X3w;
end

%% ----------------------------
% 4) Build Tensor & Run CP-ALS
% -----------------------------
R = params.Rank;

% CP-ALS options
opts = struct;
opts.printitn = 1;      % Print every n iterations (0 = silent)
opts.maxiters = 500;
opts.tol = 1e-6;

fprintf('Running CP-ALS (rank %d).\n', R);
cp = cp_als(T, R, 'printitn', opts.printitn, 'tol', opts.tol, 'maxiters', opts.maxiters);

% Unpack factors (always 3 modes now)
% mode-1=A (channels), mode-2=B (time or freq*time), mode-3=C (subjects)
A = cp.U{1};    % [C x R]
B = cp.U{2};    % [T x R] or [F*T x R]
C = cp.U{3};    % [S x R]

% Flip spatial/time factors together to preserve the tensor and positive temporal peaks.
for r = 1:R
    [~, iMax] = max(abs(B(:, r)));
    sgn = sign(B(iMax, r));
    if sgn == 0, sgn = 1; end
    A(:, r) = sgn * A(:, r);
    B(:, r) = sgn * B(:, r);
end
cp.U = {A, B, C};

expl_var = 1 - (norm(T - full(cp)) / norm(T))^2;
fprintf('Pseudo explained variance: %.2f%%\n', 100 * expl_var);

%% ----------------------------
% 5) Pack Outputs
% -----------------------------
out = struct();
out.T = T;
out.cp = cp;
out.A = A;
out.B = B;
out.C = C;
out.is_tfr = is_tfr;
out.chanlocs = Out.meta.chanlocs;
out.fs = srate;
out.tvec = tvec;
out.subjects = subjects;
out.minT = minT;
out.SubjectPrefix = params.SubjectPrefix;

if is_tfr
    out.fvec = fvec;
    out.minF = minF;
end


%% ----------------------------
% 6) Optional Plotting
% -----------------------------
if params.Plot
    movie.plot_cp(out);
end


end
