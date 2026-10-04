function on_test_clicks_(obj)
if ~obj.apply_controls_to_engine_()
    return
end
[durs, levels, repeatCount, wasCancelled] = obj.prompt_click_test_parameters_();
if wasCancelled
    obj.set_status_('Click LUT test cancelled.', false);
    return
end
obj.with_busy_state_(@() obj.run_test_clicks_(durs, levels, repeatCount), ...
    'Testing click lookup table...', true);
end
