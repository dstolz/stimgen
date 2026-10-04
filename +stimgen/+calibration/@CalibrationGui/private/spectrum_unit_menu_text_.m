function s = spectrum_unit_menu_text_(unit)
% s = spectrum_unit_menu_text_(unit)
% Menu caption for a LiveMonitor spectrum unit: what the unit is for, with the
% unit itself in parentheses. The list of units belongs to the monitor; only
% the wording of it belongs here, and an unlisted unit still gets an item
% rather than an error.

switch unit
    case "dB SPL",      s = 'Sound Pressure Level (dB SPL)';
    case "dB SPL/Hz",   s = 'Spectral Density (dB SPL/Hz)';
    case "Pa",          s = 'Sound Pressure (Pa rms)';
    case "V",           s = 'Measured Voltage (V rms)';
    case "dBV",         s = 'Measured Voltage (dB re 1 V)';
    case "V/sqrt(Hz)",  s = 'Voltage Density (V/sqrt(Hz))';
    case "dB re peak",  s = 'Relative to Peak (dB)';
    otherwise,          s = char(unit);
end
end
