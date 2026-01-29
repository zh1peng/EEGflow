function register_op(reg, op, fn)
    if ~isa(fn, 'function_handle')
        error('Registry:BadHandle', 'Value for %s must be a function_handle.', op);
    end
    if reg.isKey(op)
        error('Registry:DuplicateOp', 'Operation "%s" already registered.', op);
    end
    reg(op) = fn;
end
