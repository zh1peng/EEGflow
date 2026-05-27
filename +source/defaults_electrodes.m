function defaults = defaults_electrodes()
%DEFAULTS_ELECTRODES Source electrode parameter defaults.

    defaults = struct();
    defaults.ElectrodeTemplate = 'fieldtrip_standard_1005';
    defaults.ElectrodePath = '';
    defaults.TemplateElecFile = '';
    defaults.Elec = [];
    defaults.Unit = 'mm';
    defaults.RealignMethod = 'none';
    defaults.PlotQC = true;
    defaults.ReviewRequired = true;
end
