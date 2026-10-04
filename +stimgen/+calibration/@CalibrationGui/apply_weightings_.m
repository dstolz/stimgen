function apply_weightings_(obj)
% Push the checked set to the monitor, which owns the curves, and
% redraw so the change shows without waiting for a measurement.
% Every panel is redrawn, not just the one on top: an overlay is
% an annotation on each view that can carry one, and a user who
% turns on A-weighting while reading the noise floor should not
% have to switch tabs to make it appear.
checked = arrayfun(@(h) strcmp(h.Checked, 'on'), obj.WeightingMenus);
obj.Monitor.Weightings = ...
    stimgen.calibration.LiveMonitor.WeightingTypes(checked);
obj.redraw_transfer_panels_();
end
