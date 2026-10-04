function on_calibrate_lut_(obj, kind)
% on_calibrate_lut_(obj, kind) - Calibrate Tones / Calibrate Clicks button.
% Asks for the sweep's points (and refinement, when Iterative Level
% Refinement is checked) before the busy state, then runs it.
if ~obj.apply_controls_to_engine_()
    return
end
s = obj.lut_spec_(kind);
[points, repeatCount, refine, wasCancelled] = obj.prompt_vector_parameter_( ...
    s.SweepPrompt{:}, obj.IterativeCheck.Value);
if wasCancelled
    obj.set_status_(sprintf('%s calibration cancelled.', s.Label), false);
    return
end
obj.with_busy_state_(@() obj.run_calibrate_lut_(kind, points, repeatCount, refine), ...
    sprintf('Running %s calibration...', s.Name), true);
end
