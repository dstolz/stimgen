function run_test_lut_(obj, kind, points, levels, repeatCount)
% run_test_lut_(obj, kind, points, levels, repeatCount)
% Verify the tone or click LUT empirically: Engine.test_tones/test_clicks
% plays each point at the drive voltage the table asks for and compares the
% level that comes back to the one requested. Stored in
% CalibrationData.toneTest/clickTest by the engine.
s = obj.lut_spec_(kind);
obj.focus_sweep_panel_(kind + "_test");

% points are in the GUI's unit (see lut_spec_). The plots are deliberately
% left showing the test's own curve rather than refreshed back to the
% committed LUTs -- the measured level against the requested one is the
% result.
r = s.Test(points ./ s.GuiPerEngineUnit, levels, repeatCount);

if r.passed
    verdict = 'PASS';
else
    verdict = 'FAIL';
end
msg = s.Verdict(r, verdict);

nSkipped = numel(r.skipped.(s.XField));
if nSkipped > 0
    msg = sprintf('%s %d point(s) skipped as unreachable.', msg, nSkipped);
end
obj.set_status_(msg, ~r.passed);

if ~r.passed
    uialert(obj.Figure, sprintf('%s\n\n%s', msg, s.Advice), s.AlertTitle, Icon='warning');
end
end
