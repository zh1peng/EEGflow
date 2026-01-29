function reg = init_registry()
%INIT_REGISTRY Deprecated. Use flow.Registry('prep') instead.
    warning('EEGflow:Deprecated', ...
        'prep.init_registry is deprecated. Use flow.Registry(''prep'') instead.');
    reg = flow.Registry('prep');
end
