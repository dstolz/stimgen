function build_excitation_dialog_(obj, g)
% Rows of the Excitation Settings window (see
% create_settings_dialogs_); SettingsDialog adds the Close row.
obj.ExcitationField = numeric_row_(g, 1, 'Excitation Voltage (V)', ...
    [eps, 10], '%.3f');
obj.ToneRampField = numeric_row_(g, 2, 'Tone Rise/Fall Time (ms)', ...
    [0.1, 50], '%.2f', ...
    stimgen.util.tooltip('CalibrationGui', 'ToneRampDuration'));

obj.ExcitationField.ValueChangedFcn = @(~,~) obj.on_excitation_setting_changed_();
obj.ToneRampField.ValueChangedFcn = @(~,~) obj.on_excitation_setting_changed_();
end
