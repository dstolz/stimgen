function run_calibrate_clicks_(obj, durs, repeatCount, refine)
obj.focus_sweep_panel_("click");
if isempty(durs)
    obj.Engine.calibrate_clicks([], repeatCount);
else
    % Prompt is in ms; Engine.calibrate_clicks takes seconds.
    obj.Engine.calibrate_clicks(durs ./ 1e3, repeatCount);
end
if isempty(refine)
    obj.refresh_all_plots_();
    obj.update_runtime_state_();
    obj.set_status_('Click calibration complete.', false);
    return
end

% The sweep's own averaging carries into the refinement passes:
% what was accurate enough to build the table is accurate enough
% to correct it.
obj.set_status_('Click calibration complete. Refining against measured levels...', false);
drawnow;
r = obj.Engine.refine_clicks( ...
    MaxIterations=refine.MaxIterations, ...
    ToleranceDb=refine.ToleranceDb, ...
    RepeatCount=repeatCount);
obj.refresh_all_plots_();
obj.update_runtime_state_();
obj.report_refinement_(r, 'Click');
end
