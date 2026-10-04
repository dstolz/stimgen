function build_delay_dialog_(obj, g)
% Rows of the Conduction Delay Settings window (see
% create_settings_dialogs_); SettingsDialog adds the Close row.
obj.DelayMaxField = numeric_row_(g, 1, 'Largest Delay to Search (ms)', ...
    [0.01, 10000], '%.1f', ...
    stimgen.util.tooltip('CalibrationGui', 'DelayMaxDelay'));

obj.DelayClicksField = numeric_row_(g, 2, 'Clicks in Probe Train', ...
    [1, 1000], '%d', ...
    stimgen.util.tooltip('CalibrationGui', 'DelayNumClicks'));
obj.DelayClicksField.RoundFractionalValues = 'on';

% A rig fact rather than a probe parameter, and here rather than
% with the other rig facts because this is the window it is read
% on: a delay is only a distance once the air it crossed has a
% temperature. In degrees Celsius, the unit the Engine, the .esgc
% file, describe() and the log all use -- one unit everywhere, so
% no reading has to be converted to be compared with another.
obj.AmbientTempField = numeric_row_(g, 4, 'Ambient Temperature (°C)', ...
    obj.AmbientTempLimitsC, '%.1f', ...
    stimgen.util.tooltip('CalibrationGui', 'AmbientTemperature'));

% What the prompt used to say on its way past. It is instruction
% rather than setting, and it is only true while this window is
% the one being read, so it stays on it.
hint = uilabel(g, WordWrap='on', ...
    Text=['A brief click is played and the delay of its response ' ...
    'measured. Leave the speaker and microphone where an experiment ' ...
    'has them, and take the acoustic calibrator off the microphone, ' ...
    'then close this window and press Measure Conduction Delay.']);
hint.Layout.Row = 5;
hint.Layout.Column = [1 2];

obj.DelayMaxField.ValueChangedFcn = @(~,~) obj.on_delay_setting_changed_();
obj.DelayClicksField.ValueChangedFcn = @(~,~) obj.on_delay_setting_changed_();
obj.AmbientTempField.ValueChangedFcn = @(~,~) obj.on_ambient_temp_changed_();
end
