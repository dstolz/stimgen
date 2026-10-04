function on_test_lut_(obj, kind)
% on_test_lut_(obj, kind) - Test Tone LUT / Test Click LUT button.
% Asks for the point/level grid before the busy state, then runs the test.
if ~obj.apply_controls_to_engine_()
    return
end
s = obj.lut_spec_(kind);
[points, levels, repeatCount, wasCancelled] = obj.prompt_test_grid_(s.TestPrompt{:});
if wasCancelled
    obj.set_status_(sprintf('%s LUT test cancelled.', s.Label), false);
    return
end
obj.with_busy_state_(@() obj.run_test_lut_(kind, points, levels, repeatCount), ...
    sprintf('Testing %s lookup table...', s.Name), true);
end
