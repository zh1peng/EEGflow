function cache_file = tf_cache_save(Out_tfd, args)
%TF_CACHE_SAVE Save TF output struct to a .mat cache.
%
% Args:
%   path (char)      folder to save cache
%   basename (char)  default 'tf_cache'
%   overwrite (bool) default false

    if nargin < 2, args = struct(); end
    if ~isfield(args, 'path'), args.path = pwd; end
    if ~isfield(args, 'basename'), args.basename = 'tf_cache'; end
    if ~isfield(args, 'overwrite'), args.overwrite = false; end

    if ~exist(args.path, 'dir')
        mkdir(args.path);
    end
    cache_file = fullfile(args.path, [args.basename '.mat']);
    if exist(cache_file, 'file') && ~args.overwrite
        error('Cache file exists: %s (set overwrite=true)', cache_file);
    end

    save(cache_file, 'Out_tfd', '-v7.3');
    fprintf('TF cache saved: %s\n', cache_file);
end
