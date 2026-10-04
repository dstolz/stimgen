function [points, levels, repeatCount, wasCancelled] = prompt_test_grid_(obj, dlgTitle, what, pointLabel, pointTip, levelLabel, levelTip, pointPref, levelPref, repeatPref)
% The window behind both LUT tests: the points, the levels and
% the averages, typed and validated before the busy state.
tip = @(k) stimgen.util.tooltip('CalibrationGui', k);
specs = [ ...
    param_spec_("points", pointLabel, "text", obj.get_pref_(pointPref, ''), ...
        Tip=tip(pointTip), ...
        Validate=@(t) vector_or_empty_(t, sprintf('test %s points', what))), ...
    param_spec_("levels", levelLabel, "text", obj.get_pref_(levelPref, ''), ...
        Tip=tip(levelTip), ...
        Validate=@(t) vector_or_empty_(t, 'requested levels')), ...
    param_spec_("repeats", "Number of Averages", "integer", ...
        pref_number_(obj.get_pref_(repeatPref, '2'), 2, [1 1000], false), ...
        Limits=[1 1000], Format='%d', Tip=tip('DlgRepeats'))];

[v, ok, raw] = parameter_dialog_(obj.Figure, dlgTitle, '', specs);
wasCancelled = ~ok;
if ~ok
    points = [];
    levels = [];
    repeatCount = 2;
    return
end
points      = v.points;
levels      = v.levels;
repeatCount = v.repeats;
obj.set_pref_(pointPref, raw.points);
obj.set_pref_(levelPref, raw.levels);
obj.set_pref_(repeatPref, sprintf('%d', repeatCount));
end
