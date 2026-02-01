function reg = register_new_op(op, fn, varargin)
%REGISTER_NEW_OP Create a prep registry and add/override an op.
%
% Usage:
%   reg = prep.register_new_op('my_step', @my_step);
%   reg = prep.register_new_op(reg, 'my_step', @my_step);
%   reg = prep.register_new_op(reg, 'my_step', @my_step, 'AllowOverride', true);

    if nargin < 2
        error('prep:register_new_op:MissingArgs', 'Need (op, fn) or (reg, op, fn).');
    end

    if isa(op, 'containers.Map')
        reg = op;
        if nargin < 3
            error('prep:register_new_op:MissingArgs', 'Need (reg, op, fn).');
        end
        opName = fn;
        fnHandle = varargin{1};
        extra = varargin(2:end);
    else
        reg = init_registry();
        opName = op;
        fnHandle = fn;
        extra = varargin;
    end

    if ~isa(fnHandle, 'function_handle')
        error('prep:register_new_op:BadFn', 'fn must be a function_handle.');
    end

    % optional override flag
    allowOverride = false;
    if ~isempty(extra)
        p = inputParser;
        p.addParameter('AllowOverride', false, @(x) islogical(x) && isscalar(x));
        p.parse(extra{:});
        allowOverride = p.Results.AllowOverride;
    end

    opKey = char(opName);
    if reg.isKey(opKey) && ~allowOverride
        error('prep:register_new_op:DuplicateOp', ...
            'Operation "%s" already exists. Set AllowOverride=true to replace it.', opKey);
    end

    reg(opKey) = fnHandle;
end
