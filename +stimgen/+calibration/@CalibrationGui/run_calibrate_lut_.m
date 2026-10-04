function run_calibrate_lut_(obj, kind, points, repeatCount, refine)
% run_calibrate_lut_(obj, kind, points, repeatCount, refine)
% Run a tone or click sweep, then the refinement when one was asked for.
% points are in the GUI's unit (see lut_spec_); empty hands the choice to
% the engine's default list.
s = obj.lut_spec_(kind);
obj.focus_sweep_panel_(kind);
s.Calibrate(points ./ s.GuiPerEngineUnit, repeatCount);
if isempty(refine)
    obj.refresh_all_plots_();
    obj.update_runtime_state_();
    obj.set_status_(sprintf('%s calibration complete.', s.Label), false);
    return
end

% The sweep's own averaging carries into the refinement passes:
% what was accurate enough to build the table is accurate enough
% to correct it.
obj.set_status_(sprintf('%s calibration complete. Refining against measured levels...', ...
    s.Label), false);
drawnow;
r = s.Refine(refine.MaxIterations, refine.ToleranceDb, repeatCount);
obj.refresh_all_plots_();
obj.update_runtime_state_();
obj.report_refinement_(r, s.Label);
end
