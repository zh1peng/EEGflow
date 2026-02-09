function Out_tfd = tf_cache_load(args)
%TF_CACHE_LOAD Load TF output struct from a .mat cache.
%
% Args:
%   file (char)      full path to cache file
%   path (char)      folder
%   basename (char)  default 'tf_cache'

    if nargin < 1, args = struct(); end
    if ischar(args) || isstring(args)
        args = struct('file', char(args));
    end
    if ~isfield(args, 'file')
        if ~isfield(args, 'path'), args.path = pwd; end
        if ~isfield(args, 'basename'), args.basename = 'tf_cache'; end
        args.file = fullfile(args.path, [args.basename '.mat']);
    end
    if ~exist(args.file, 'file')
        error('Cache file not found: %s', args.file);
    end
    S = load(args.file);
    if ~isfield(S, 'Out_tfd')
        error('Cache file missing Out_tfd: %s', args.file);
    end
    Out_tfd = S.Out_tfd;
    fprintf('TF cache loaded: %s\n', args.file);
end
