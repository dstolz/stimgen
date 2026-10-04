function [values, repeatCount, refine, wasCancelled] = prompt_vector_parameter_(obj, prefName, repeatPrefName, label, tipKey, dlgTitle, includeRefinement)
% [values, repeatCount, refine, wasCancelled] = prompt_vector_parameter_(...)
% The parameter window of a tone or click sweep: the list of
% points (a typed text field, since a list is entered as numbers
% or a MATLAB expression such as 500.*2.^(0:.5:5); empty means the
% engine's default series) and the number of averages. With
% includeRefinement set (the Iterative Level Refinement toggle) it
% also collects the refinement's pass limit and accuracy target,
% so the whole run is parameterized in one place before any
% hardware moves. Everything is validated before the window
% closes, and the window is raised before the busy state.
%
% values are in the field's own unit (Hz, or ms for clicks);
% refine is [] when the toggle is off, or a struct with
% MaxIterations and ToleranceDb.
arguments
    obj
    prefName (1,:) char
    repeatPrefName (1,:) char
    label (1,1) string
    tipKey (1,:) char
    dlgTitle (1,:) char
    includeRefinement (1,1) logical = false
end
tip = @(k) stimgen.util.tooltip('CalibrationGui', k);
refine = [];
specs = [ ...
    param_spec_("values", label, "text", obj.get_pref_(prefName, ''), ...
        Tip=tip(tipKey), Validate=@(t) vector_or_empty_(t, lower(label))), ...
    param_spec_("repeats", "Number of Averages", "integer", ...
        pref_number_(obj.get_pref_(repeatPrefName, '1'), 1, [1 1000], false), ...
        Limits=[1 1000], Format='%d', Tip=tip('DlgRepeats'))];
if includeRefinement
    specs = [specs, ...
        param_spec_("maxPasses", "Refinement: Maximum Test Passes", "integer", ...
            pref_number_(obj.get_pref_('refineMaxPasses', '3'), 3, [1 100], false), ...
            Limits=[1 100], Format='%d', Tip=tip('DlgRefineMaxPasses')), ...
        param_spec_("tolerance", "Refinement: Target Accuracy (dB)", "numeric", ...
            pref_number_(obj.get_pref_('refineToleranceDb', '1'), 1, [0 60], true), ...
            Limits=[0 60], LowerOpen=true, Format='%.3g', ...
            Tip=tip('DlgRefineTolerance'))];
end

[v, ok, raw] = parameter_dialog_(obj.Figure, dlgTitle, '', specs);
wasCancelled = ~ok;
if ~ok
    values = [];
    repeatCount = 1;
    return
end
values = v.values;
repeatCount = v.repeats;
obj.set_pref_(prefName, raw.values);
obj.set_pref_(repeatPrefName, sprintf('%d', repeatCount));
if includeRefinement
    refine = struct('MaxIterations', v.maxPasses, 'ToleranceDb', v.tolerance);
    obj.set_pref_('refineMaxPasses', sprintf('%d', v.maxPasses));
    obj.set_pref_('refineToleranceDb', sprintf('%.15g', v.tolerance));
end
end
