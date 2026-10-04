function build_verification_section_(obj, g)
% The two lookup-table tests share the top row, each under the
% sweep it verifies in the section above. Both are ahead of the
% equalizer: a filter designed on a table whose levels are wrong
% inherits that error. Design and its own verification then share
% the row below, since neither is much use without the other. The
% export of the taps gets the full width under both, being the one
% thing here that leaves the window.
obj.BtnTestTones = action_button_(g, 1, 1, 'Test Tones', ...
    'BtnTestTones', @(~,~) obj.on_test_lut_("tone"));
obj.BtnTestClicks = action_button_(g, 1, 2, 'Test Clicks', ...
    'BtnTestClicks', @(~,~) obj.on_test_lut_("click"));
obj.BtnFilter = action_button_(g, 2, 1, 'Design Filter', ...
    'BtnFilter', @(~,~) obj.on_design_filter_());
obj.BtnTestFilter = action_button_(g, 2, 2, 'Test Filter', ...
    'BtnTestFilter', @(~,~) obj.on_test_filter_());
obj.BtnCopyFilter = action_button_(g, 3, [1 2], 'Copy Filter Coefficients', ...
    'BtnCopyFilter', @(~,~) obj.on_copy_filter_coefficients_());

% What the equalizer does to a level once it runs in hardware,
% where nothing renormalizes after the FIR. Shown for the 1 V RMS
% white-noise convention; Engine.filter_level_reference takes the
% actual source waveform when that assumption does not hold.
obj.LevelRefLabel = readout_row_(g, 4, 'Unity-Gain Noise Level', ...
    'Not designed', ...
    stimgen.util.tooltip('CalibrationGui', 'FilterLevelReference'));
end
