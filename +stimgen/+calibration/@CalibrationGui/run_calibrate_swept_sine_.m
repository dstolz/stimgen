function run_calibrate_swept_sine_(obj, duration, freqs, repeatCount)
obj.focus_sweep_panel_("swept_sine");
if isempty(freqs)
    obj.Engine.calibrate_swept_sine(duration, [], repeatCount);
else
    obj.Engine.calibrate_swept_sine(duration, freqs, repeatCount);
end
obj.refresh_all_plots_();
obj.update_runtime_state_();
obj.set_status_('Swept sine calibration complete.', false);
end
