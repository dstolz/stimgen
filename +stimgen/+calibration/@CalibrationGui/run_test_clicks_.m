function run_test_clicks_(obj, durs, levels, repeatCount)
% Verify the click LUT empirically: Engine.test_clicks plays clicks
% at the drive voltages the table asks for and compares the levels
% that come back to the ones requested. Stored in
% CalibrationData.clickTest by the engine.
obj.focus_sweep_panel_("click_test");

% Prompt is in ms; Engine.test_clicks takes seconds. The plots are
% deliberately left showing the test's own curve rather than
% refreshed back to the committed LUTs -- the measured level
% against the requested one is the result.
r = obj.Engine.test_clicks(durs ./ 1e3, levels, RepeatCount=repeatCount);

if r.passed
    verdict = 'PASS';
else
    verdict = 'FAIL';
end
msg = sprintf( ...
    'Click LUT test %s: worst error %.2f dB at %.1f \x00B5s / %g dB peSPL, bias %+.2f dB (tolerance %.1f dB).', ...
    verdict, r.max_abs_error_db, r.worst.duration * 1e6, ...
    r.worst.level_db, r.bias_db, r.tolerance_db);

nSkipped = numel(r.skipped.duration);
if nSkipped > 0
    msg = sprintf('%s %d point(s) skipped as unreachable.', msg, nSkipped);
end
obj.set_status_(msg, ~r.passed);

if ~r.passed
    uialert(obj.Figure, sprintf(['%s\n\nLevels are not being reproduced within ' ...
        'tolerance. A uniform bias usually means the reference measurement ' ...
        'moved since the sweep; errors at scattered durations ' ...
        'mean the table is too sparse to interpolate through -- recalibrate ' ...
        'clicks with a finer duration list. Very short clicks are the first to ' ...
        'fail on SNR, since they put little energy into the room.'], msg), ...
        'Click LUT Test Failed', Icon='warning');
end
end
