function on_calibrate_swept_sine_(obj)
if ~obj.apply_controls_to_engine_()
    return
end
[duration, freqs, repeatCount, wasCancelled] = obj.prompt_swept_sine_parameters_();
if wasCancelled
    obj.set_status_('Swept sine calibration cancelled.', false);
    return
end
obj.with_busy_state_(@() obj.run_calibrate_swept_sine_(duration, freqs, repeatCount), ...
    'Running swept sine calibration...', true);
end
