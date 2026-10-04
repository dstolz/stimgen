function on_test_tones_(obj)
if ~obj.apply_controls_to_engine_()
    return
end
[freqs, levels, repeatCount, wasCancelled] = obj.prompt_tone_test_parameters_();
if wasCancelled
    obj.set_status_('Tone LUT test cancelled.', false);
    return
end
obj.with_busy_state_(@() obj.run_test_tones_(freqs, levels, repeatCount), ...
    'Testing tone lookup table...', true);
end
