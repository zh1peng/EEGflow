function [W, ISC, Y, A, p] = run_corrca(data_struct, varargin)
% RUN_CORRCA Perform Correlated Component Analysis (CorrCA) on data from collect_segments.
% 
%   This function serves as a wrapper for the `corrca` function, adapting the
%   output of `movie.collect_segments` into the required format for the analysis.
%   It extracts the data for each subject, stacks it into the specified
%   [time x dimensions x subjects] matrix, and then executes the CorrCA.
% 
% Usage:
%   [W, ISC, Y, A, p] = movie.run_corrca(data_struct)
%   [W, ISC, Y, A, p] = movie.run_corrca(data_struct, 'shrinkage', 0.1, 'tsvd', 10)
% 
% Inputs:
%   data_struct (struct):
%       The output structure from `movie.collect_segments`. This struct must
%       contain a `meta` field and one or more `sub_...` fields, where each
%       subject field holds a `data` matrix of size [channels x time].
% 
%   varargin:
%       Optional name-value pair arguments to be passed directly to the
%       `corrca` function. Common options include:
%       - 'shrinkage': Shrinkage regularization parameter (e.g., 0.1).
%       - 'tsvd': Truncate eigenvalue spectrum to K components.
%       - 'version': Algorithm version (1, 2, or 3). Default is 2.
%       - 'fixed': Evaluate for a given projection matrix W.
% 
% Outputs:
%   W (matrix):
%       The projection vectors (spatial filters) that maximize inter-subject
%       correlation. Size is [channels x components].
% 
%   ISC (vector):
%       The inter-subject correlation values for each component.
% 
%   Y (3D matrix):
%       The projected data for each subject. Size is [time x components x subjects].
% 
%   A (matrix):
%       The forward model (activation patterns) for each component. Size is
%       [channels x components].
% 
%   p (vector):
%       P-values for each component's ISC, computed only if 'fixed' option is used.
% 
% Example:
%   % First, extract movie data segments for all subjects
%   MovieData = movie.collect_segments( ...
%       'study_path', 'C:\EEG_Data\MovieStudy', ...
%       'StartMarker', 'movie_start', ...
%       'EndMarker', 'movie_end', ...
%       'chan_exclude', {'HEOG', 'VEOG'});
% 
%   % Ensure the data is not empty
%   if isempty(fieldnames(MovieData))
%       error('No subjects found in the extracted data.');
%   end
% 
%   % Run CorrCA on the extracted data using shrinkage regularization
%   [W, ISC] = movie.run_corrca(MovieData, 'shrinkage', 0.1);
% 
%   % Plot the top component's activation pattern
%   top_component_pattern = A(:, 1);
%   topoplot(top_component_pattern, MovieData.meta.chanlocs);
%   title('Forward Model of Component with Highest ISC');
% 
% See also: movie.collect_segments, corrca

%% ---- Input Validation
if ~isstruct(data_struct) || ~isfield(data_struct, 'meta')
    error('Input must be a valid data structure from movie.collect_segments, containing a `meta` field.');
end

if ~exist('corrca.m', 'file')
    error('`corrca.m` not found. Ensure the required toolbox is in your MATLAB path.');
end

%% ---- Data Preparation
% Get all subject field names (e.g., 'sub_001', 'sub_s02')
all_fields = fieldnames(data_struct);
sub_fields = all_fields(startsWith(all_fields, 'sub_'));

if isempty(sub_fields)
    error('No subject data (fields starting with "sub_") found in the input structure.');
end

% subject_data_cell = cell(1, numel(sub_fields));
min_timepoints = inf;
num_channels = []; % Initialize num_channels

for i = 1:numel(sub_fields)
    sub_key = sub_fields{i};
    if isfield(data_struct.(sub_key), 'data') && ~isempty(data_struct.(sub_key).data)
        
        sub_data = data_struct.(sub_key).data; % This is [channels x time]
        
        % Set number of channels from the first valid subject
        if isempty(num_channels)
            num_channels = size(sub_data, 1); % Get channel count from 1st dimension
        elseif size(sub_data, 1) ~= num_channels
            warning('Subject %s has a different number of channels. Expected %d, got %d.', sub_key, num_channels, size(sub_data, 1));
            subject_data_cell{i} = []; % Skip this subject
            continue;
        end

        % Data is [channels x time], transpose to [time x channels]
        subject_data_cell{i} = sub_data';
        
        % Keep track of the minimum number of timepoints across subjects
        current_timepoints = size(sub_data, 2); % Get timepoint count from 2nd dimension
        if current_timepoints < min_timepoints
            min_timepoints = current_timepoints;
        end
    else
        warning('Subject %s has empty data and will be skipped.', sub_key);
        subject_data_cell{i} = [];
    end
end

% Filter out empty entries
subject_data_cell = subject_data_cell(~cellfun('isempty', subject_data_cell));

if isempty(subject_data_cell)
    error('No valid subject data could be collected from the input structure.');
end

if isempty(num_channels)
    error('Could not determine the number of channels from the data.');
end

%% ---- Assemble 3D Matrix
% Trim all subjects to the same length (the minimum) to create a regular matrix
num_subjects = numel(subject_data_cell);

X = zeros(min_timepoints, num_channels, num_subjects);

for i = 1:num_subjects
    X(:, :, i) = subject_data_cell{i}(1:min_timepoints, :);
end

fprintf('Data prepared for CorrCA: %d timepoints, %d channels, %d subjects.\n', ...
    min_timepoints, num_channels, num_subjects);

%% ---- Run CorrCA
fprintf('Data prepared for CorrCA: %d timepoints, %d channels, %d subjects.\n', ...
    min_timepoints, num_channels, num_subjects);

% Call corrca with the number of outputs requested by the user
switch nargout
    case 0 % No outputs requested, just run
        corrca(X, varargin{:});
        fprintf('CorrCA complete. No outputs were requested.\n');
        % Assign empty to outputs that might be expected in some cases
        W = []; ISC = []; Y = []; A = []; p = [];
    case 1
        [W] = corrca(X, varargin{:});
        fprintf('CorrCA complete. Found %d components.\n', size(W, 2));
    case 2
        [W, ISC] = corrca(X, varargin{:});
        fprintf('CorrCA complete. Found %d components.\n', numel(ISC));
    case 3
        [W, ISC, Y] = corrca(X, varargin{:});
        fprintf('CorrCA complete. Found %d components.\n', numel(ISC));
    case 4
        [W, ISC, Y, A] = corrca(X, varargin{:});
        fprintf('CorrCA complete. Found %d components.\n', numel(ISC));
    case 5
        % The 'p' output is only generated when 'fixed' is in varargin
        is_fixed = any(strcmpi('fixed', varargin));
        if ~is_fixed
            error('Requesting 5 output arguments (including p-values) requires passing the fixed name-value pair to the function.');
        end
        [W, ISC, Y, A, p] = corrca(X, varargin{:});
        fprintf('CorrCA complete. Found %d components.\n', numel(ISC));
    otherwise
        error('Too many output arguments requested.');
end



% -------------------------------------------------------------------------
function Xr = phaserandomized(X);
% Generate phase randomized surrogate data Xr that preserves spatial and
% temporal correlation in X, following Prichard D, Theiler J. Generating 
% surrogate data for time series with several simultaneously measured 
% variables. Physical review letters. 1994 Aug 15;73(7):951.

[T,D,N] = size(X);

Tr = round(T/2)*2; % this code only works if T is even; make it so
for i = 1:N
    Xfft = fft(X(:,:,i),Tr); % will add a zero at the end if uneven length
    Amp = abs  (Xfft(1:Tr/2+1,:)); % original amplitude
    Phi = angle(Xfft(1:Tr/2+1,:)); % orignal phase
    Phir = 4*acos(0)*rand(Tr/2-1,1)-2*acos(0); % random phase to add
    tmp(2:Tr/2,:) = Amp(2:Tr/2,:).*exp(sqrt(-1)*(Phi(2:Tr/2,:)+repmat(Phir,1,D))); % Theiler's magic
    tmp = ifft([Xfft(1,:); tmp(2:Tr/2,:); Xfft(Tr/2+1,:); conj(tmp(Tr/2:-1:2,:))]); % resynthsized keeping it real
    Xr(:,:,i) = tmp(1:T,:,:); % grab only the original length
end


