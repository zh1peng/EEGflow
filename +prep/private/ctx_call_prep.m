function [EEG, out] = ctx_call_prep(fn, varargin)
%CTX_CALL_PREP Call legacy prep function with safe output handling
% If the target has only 1 output, return empty struct for out.
    out = struct();
    nout = -1;
    try
        nout = nargout(fn);
    catch
        nout = -1;
    end
    if nout < 0 || nout >= 2
        [EEG, out] = fn(varargin{:});
    else
        EEG = fn(varargin{:});
    end
end
