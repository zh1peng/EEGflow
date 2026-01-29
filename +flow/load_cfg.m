function cfg = load_cfg(configPath)
%LOAD_CFG Read and normalize a JSON config file for EEGflow.
%
% Usage:
%   cfg = flow.load_cfg('path/to/prep_config.json');
%
% This wraps jsondecode + normalization so downstream code receives
% consistent MATLAB types (char, cellstr, row vectors).

    if nargin < 1 || isempty(configPath)
        error('flow:load_cfg:MissingPath', 'configPath is required.');
    end
    cfg = jsondecode(fileread(configPath));
    cfg = normalize_cfg(cfg);
end
