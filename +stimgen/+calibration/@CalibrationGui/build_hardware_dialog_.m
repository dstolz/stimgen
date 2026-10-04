function build_hardware_dialog_(obj, g)
% Rows of the Hardware and Analysis Settings window (see
% create_settings_dialogs_); SettingsDialog adds the Close row.
obj.SampleRateLabel = readout_row_(g, 1, 'Sample Rate', 'No adapter', '');

obj.MaxOutputField = numeric_row_(g, 2, 'Max Output Voltage (V)', ...
    [eps, 1000], '%.1f', stimgen.util.tooltip('CalibrationGui', 'MaxOutputVoltage'));

% An acquisition setting, not a display one: it changes the
% numbers that go into the table, not how they are drawn. The
% corner frequency is fixed at Engine's 20 Hz default and is not
% exposed here.
obj.AcCoupleCheck = check_row_(g, 3, 'AC Couple Acquired Signal', ...
    stimgen.util.tooltip('CalibrationGui', 'AcCoupleResponse'));

% Neither of the two below is read by anything: the sweep was
% measured through whatever gain the rig was set to, so both are
% already inside every voltage in the tables, and applying one
% again would double-count it. They are here so the file records
% the knob positions it was made at -- the one fact a table
% cannot be checked against later. The heading says so, because
% a gain field on a calibration window otherwise reads as one
% that is applied.
heading_row_(g, 5, 'Hardware Gain (recorded, not applied)');

obj.AdcGainField = numeric_row_(g, 6, 'ADC Gain (dB)', ...
    [-200, 200], '%.1f', stimgen.util.tooltip('CalibrationGui', 'AdcGain'));

obj.DacAttenField = numeric_row_(g, 7, 'DAC Attenuation (dB)', ...
    [-200, 200], '%.1f', stimgen.util.tooltip('CalibrationGui', 'DacAttenuation'));

% The two below are analysis rather than acquisition: they change
% how an already-acquired record is turned into a spectrum, and so
% what every level read off one becomes. They share this window
% with AC coupling because they share its consequence -- the
% numbers in the table move -- and are separated by a heading
% because the reason they move is a different one.
heading_row_(g, 9, 'Spectral Analysis');

obj.SpectralWindowDrop = dropdown_row_(g, 10, 'Analysis Window', ...
    arrayfun(@stimgen.calibration.SpectralOptions.windowLabel, ...
        stimgen.calibration.SpectralOptions.WindowList), ...
    stimgen.calibration.SpectralOptions.WindowList, ...
    stimgen.util.tooltip('CalibrationGui', 'SpectralWindow'));

obj.SpectralFftDrop = dropdown_row_(g, 11, 'FFT Length (samples)', ...
    arrayfun(@stimgen.calibration.SpectralOptions.fftLengthLabel, ...
        stimgen.calibration.SpectralOptions.FftLengthList), ...
    stimgen.calibration.SpectralOptions.FftLengthList, ...
    stimgen.util.tooltip('CalibrationGui', 'SpectralFftLength'));

% Settings push to the engine as they change: the window may be
% closed by run time, so apply-at-next-run would silently depend
% on whether it happened to be open then.
obj.MaxOutputField.ValueChangedFcn = @(~,~) obj.on_hardware_setting_changed_();
obj.AcCoupleCheck.ValueChangedFcn = @(~,~) obj.on_hardware_setting_changed_();
obj.AdcGainField.ValueChangedFcn = @(~,~) obj.on_hardware_setting_changed_();
obj.DacAttenField.ValueChangedFcn = @(~,~) obj.on_hardware_setting_changed_();
obj.SpectralWindowDrop.ValueChangedFcn = @(~,~) obj.on_spectral_setting_changed_();
obj.SpectralFftDrop.ValueChangedFcn = @(~,~) obj.on_spectral_setting_changed_();

obj.refresh_sample_rate_label_();
end
