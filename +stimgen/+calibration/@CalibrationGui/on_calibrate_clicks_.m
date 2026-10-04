function on_calibrate_clicks_(obj)
if ~obj.apply_controls_to_engine_()
    return
end
[durs, repeatCount, refine, wasCancelled] = obj.prompt_vector_parameter_( ...
    'clickDurationsMs', 'clickRepeats', "Click Durations (ms)", ...
    'DlgClickDurations', 'Click Calibration', obj.IterativeCheck.Value);
if wasCancelled
    obj.set_status_('Click calibration cancelled.', false);
    return
end
obj.with_busy_state_(@() obj.run_calibrate_clicks_(durs, repeatCount, refine), ...
    'Running click calibration...', true);
end
