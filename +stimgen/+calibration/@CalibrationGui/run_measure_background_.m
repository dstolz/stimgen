function run_measure_background_(obj, p)
r = obj.Engine.measure_background(p.duration, p.records, ...
    TonalProminenceDb=p.prominence);

% Drawn, then brought to the front: the band curve is the result
% of the step just run, and the operator is about to read an
% alert about it. Nothing else is disturbed -- a sweep already on
% the Transfer Curves tab is still there afterwards, which it was
% not when the two shared a panel.
obj.Monitor.show_background(obj.Engine);
obj.set_transfer_view_("background");

hasFindings = ~isempty(r.flags);
obj.set_status_(stimgen.calibration.Engine.background_summary(r), hasFindings);

if hasFindings
    icon = 'warning';
else
    icon = 'info';
end
uialert(obj.Figure, stimgen.calibration.Engine.background_report(r), 'Background Noise', Icon=icon);
end
