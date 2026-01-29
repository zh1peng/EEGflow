function reg = init_registry()
%INIT_REGISTRY Deprecated. Use flow.Registry() instead.
    warning('EEGflow:Deprecated', ...
        'analysis.init_registry is deprecated. Use flow.Registry() instead.');
    reg = flow.Registry();
end
