function [qc, geom, state] = inspect_headmodel(eegOrSetFile, varargin)
%INSPECT_HEADMODEL Standalone helper for human headmodel/electrode QC.
%
% Usage:
%   qc = source.inspect_headmodel(EEG, 'HeadModelPath', hm, 'TemplateElecFile', elec)
%   qc = source.inspect_headmodel(setFile, 'HeadModelPath', hm, 'TemplateElecFile', elec)
%
% This is a convenience wrapper around source.check_headmodel. It accepts an
% EEGLAB EEG struct or a .set filepath, enables PlotQC by default, and does
% not fail on QC by default so users can inspect the returned metrics/figure.

    if nargin < 1 || isempty(eegOrSetFile)
        error('source:inspect_headmodel:MissingInput', 'Provide an EEGLAB EEG struct or a .set filepath.');
    end

    EEG = local_load_eeg(eegOrSetFile);
    args = local_parse_args(varargin{:});

    if ~isfield(args, 'PlotQC') || isempty(args.PlotQC)
        args.PlotQC = true;
    end
    if ~isfield(args, 'ReviewRequired') || isempty(args.ReviewRequired)
        args.ReviewRequired = true;
    end
    if ~isfield(args, 'FailOnQC') || isempty(args.FailOnQC)
        args.FailOnQC = false;
    end
    if ~isfield(args, 'KeepInState') || isempty(args.KeepInState)
        args.KeepInState = true;
    end

    state = struct();
    state.EEG = EEG;
    state.cfg = struct();
    state = source.check_headmodel(state, args, struct());

    qc = state.source.geometry.qc;
    geom = state.source.geometry;
end

function EEG = local_load_eeg(x)
    if isstruct(x)
        EEG = x;
        return;
    end
    if ~(ischar(x) || isstring(x))
        error('source:inspect_headmodel:BadInput', 'Input must be an EEGLAB EEG struct or a .set filepath.');
    end

    setFile = char(string(x));
    if exist(setFile, 'file') ~= 2
        error('source:inspect_headmodel:FileNotFound', 'SET file not found: %s', setFile);
    end
    if exist('pop_loadset', 'file') ~= 2
        error('source:inspect_headmodel:MissingEEGLAB', 'pop_loadset not found. Add EEGLAB to the MATLAB path.');
    end
    [fp, fn, ext] = fileparts(setFile);
    EEG = pop_loadset('filename', [fn ext], 'filepath', fp);
    if exist('eeg_checkset', 'file') == 2
        EEG = eeg_checkset(EEG);
    end
end

function args = local_parse_args(varargin)
    if isempty(varargin)
        args = struct();
        return;
    end
    if numel(varargin) == 1 && isstruct(varargin{1})
        args = varargin{1};
        return;
    end
    if mod(numel(varargin), 2) ~= 0
        error('source:inspect_headmodel:BadArgs', 'Arguments must be a struct or name-value pairs.');
    end
    args = struct();
    for i = 1:2:numel(varargin)
        name = char(string(varargin{i}));
        args.(name) = varargin{i+1};
    end
end

