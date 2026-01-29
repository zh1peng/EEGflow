function info = inspect_dataset(dataset_path, varargin)
% INSPECT_DATASET  Summarize dataset structure without loading raw data into LLMs.
%
% INPUTS
%   dataset_path : string
%       Path to dataset root or a specific file (e.g., .set or .mat).
%
% NAME-VALUE PAIRS
%   'MaxEvents'  : integer (default 50)
%       Maximum number of events to include in the summary.
%   'MaxChans'   : integer (default 64)
%       Maximum number of channel labels to include in the summary.
%   'Verbose'    : logical (default false)
%       If true, include extra fields when available.
%
% OUTPUTS
%   info : struct
%       Summary fields (paths, counts, shapes, time range, event counts).
%
% SIDE EFFECTS
%   None. This function should avoid loading full raw data arrays.
%
% NOTES
%   Implementers should use lightweight metadata reads only.
%   Do not return raw signal matrices or full event lists.

ip = inputParser;
ip.addParameter('MaxEvents', 50, @(x) isnumeric(x) && isscalar(x) && x > 0);
ip.addParameter('MaxChans', 64, @(x) isnumeric(x) && isscalar(x) && x > 0);
ip.addParameter('Verbose', false, @islogical);
ip.parse(varargin{:});
opt = ip.Results;

info = struct();
info.dataset_path = dataset_path;
info.summary_type = 'metadata_only';
info.n_files = 0;
info.n_channels = NaN;
info.n_trials = NaN;
info.time_range_ms = [];
info.channel_labels = {};
info.event_counts = struct();
info.file_index = {};
info.warnings = {};

% TODO: detect dataset root vs file, then populate fields using header-only reads.
% For now, list .set/.mat files without loading signals.
if isfolder(dataset_path)
    files = [dir(fullfile(dataset_path, '**', '*.set')); dir(fullfile(dataset_path, '**', '*.mat'))];
    info.n_files = numel(files);
    max_list = min(200, numel(files));
    info.file_index = arrayfun(@(f) fullfile(f.folder, f.name), files(1:max_list), 'UniformOutput', false);
else
    info.n_files = 1;
    info.file_index = {dataset_path};
end

info.options = opt;
end
