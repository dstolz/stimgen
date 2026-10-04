function build_reference_section_(obj, g)
% Everything about the microphone: what the acoustic calibrator
% produces, the sensitivity measuring it yields, and where the
% microphone is -- which is what the delay probe answers. The
% Ambient Temperature that probe's distance is derived at, and the
% probe's own two parameters, are settings rather than steps and
% live in their own window (on_delay_settings_).
obj.RefLevelField = numeric_row_(g, 1, 'Reference Level (dB SPL)', ...
    [1, 160], '%.1f');
obj.RefFreqField = numeric_row_(g, 2, 'Reference Frequency (Hz)', ...
    [20, 200000], '%.1f');
obj.MicSensField = numeric_row_(g, 3, 'Mic Sensitivity (V/Pa)', ...
    [eps, 100], '%.5f');

obj.BtnReference = action_button_(g, 4, 1, 'Measure Reference', ...
    'BtnReference', @(~,~) obj.on_measure_reference_());

% Background sits with the reference step, the other measurement
% that plays nothing, and after it: the noise floor is only a level
% in dB SPL once the reference has set the scale it is read on.
obj.BtnBackground = action_button_(g, 4, 2, 'Measure Background', ...
    'BtnBackground', @(~,~) obj.on_measure_background_());

obj.BtnDelay = action_button_(g, 5, [1 2], 'Measure Conduction Delay', ...
    'BtnDelay', @(~,~) obj.on_measure_delay_());
end
