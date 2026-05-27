function defaults = defaults_headmodel()
%DEFAULTS_HEADMODEL Source headmodel parameter defaults.

    defaults = struct();
    defaults.HeadModelTemplate = 'fieldtrip_standard_bem';
    defaults.HeadModelPath = '';
    defaults.HeadModel = [];
    defaults.Unit = 'mm';
    defaults.RealUnitSource = 'template';
end
