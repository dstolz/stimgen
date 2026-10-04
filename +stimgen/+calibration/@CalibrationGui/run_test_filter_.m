function run_test_filter_(obj)
% Verify the designed filter empirically: Engine.test_filter plays
% the sweep raw and through the filter and compares the flatness
% of the two measured responses. Stored in
% CalibrationData.filterTest by the engine.
obj.focus_sweep_panel_("filter_test");
r = obj.Engine.test_filter();
% The run leaves the second of its two sweeps on the panel; the
% comparison the test exists for is only drawable now that both
% have been measured.
obj.Monitor.show_filter_test(obj.Engine);
if r.passed
    verdict = 'PASS';
else
    verdict = 'FAIL';
end
msg = sprintf( ...
    'Filter test %s: ripple %.1f \x2192 %.1f dB over %g\x2013%g Hz (tolerance %.1f dB).', ...
    verdict, r.unfiltered.ripple_db, r.filtered.ripple_db, ...
    r.band(1), r.band(2), r.ripple_tolerance_db);
obj.set_status_(msg, ~r.passed);
if ~r.passed
    uialert(obj.Figure, sprintf(['%s\n\nThe equalized response still ripples more ' ...
        'than the tolerance. Consider redesigning the filter (more taps, or less ' ...
        'smoothing/correction limiting).'], msg), ...
        'Filter Test Failed', Icon='warning');
end
end
