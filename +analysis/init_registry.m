function reg = init_registry()
%INIT_REGISTRY Deprecated. Use flow.Registry('analysis') instead.
    warning('EEGflow:Deprecated', ...
        'analysis.init_registry is deprecated. Use flow.Registry(''analysis'') instead.');
    reg = flow.Registry('analysis');
end
