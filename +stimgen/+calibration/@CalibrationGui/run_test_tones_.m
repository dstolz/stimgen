function run_test_tones_(obj, freqs, levels, repeatCount)
% Verify the tone LUT empirically: Engine.test_tones plays discrete
% tones at the drive voltages the table asks for and compares the
% levels that come back to the ones requested. Stored in
% CalibrationData.toneTest by the engine.
obj.focus_sweep_panel_("tone_test");

% The plots are deliberately left showing the test's own curve
% rather than refreshed back to the committed LUTs -- the measured
% level against the requested one is the result.
r = obj.Engine.test_tones(freqs, levels, RepeatCount=repeatCount);

if r.passed
    verdict = 'PASS';
else
    verdict = 'FAIL';
end
msg = sprintf( ...
    'Tone LUT test %s (%s table): worst error %.2f dB at %.0f Hz / %g dB SPL, bias %+.2f dB (tolerance %.1f dB).', ...
    verdict, r.lut_source, r.max_abs_error_db, r.worst.frequency, ...
    r.worst.level_db, r.bias_db, r.tolerance_db);

nSkipped = numel(r.skipped.frequency);
if nSkipped > 0
    msg = sprintf('%s %d point(s) skipped as unreachable.', msg, nSkipped);
end
obj.set_status_(msg, ~r.passed);

if ~r.passed
    uialert(obj.Figure, sprintf(['%s\n\nLevels are not being reproduced within ' ...
        'tolerance. A uniform bias usually means the reference measurement ' ...
        'moved since the sweep; errors at scattered frequencies ' ...
        'mean the table is too sparse to interpolate through -- recalibrate tones ' ...
        'with a finer frequency list.'], msg), ...
        'Tone LUT Test Failed', Icon='warning');
end
end
