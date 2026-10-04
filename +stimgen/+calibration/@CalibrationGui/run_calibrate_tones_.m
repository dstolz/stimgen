function run_calibrate_tones_(obj, freqs, repeatCount, refine)
obj.focus_sweep_panel_("tone");
if isempty(freqs)
    obj.Engine.calibrate_tones([], repeatCount);
else
    obj.Engine.calibrate_tones(freqs, repeatCount);
end
if isempty(refine)
    obj.refresh_all_plots_();
    obj.update_runtime_state_();
    obj.set_status_('Tone calibration complete.', false);
    return
end

% The sweep's own averaging carries into the refinement passes:
% what was accurate enough to build the table is accurate enough
% to correct it.
obj.set_status_('Tone calibration complete. Refining against measured levels...', false);
drawnow;
r = obj.Engine.refine_tones( ...
    MaxIterations=refine.MaxIterations, ...
    ToleranceDb=refine.ToleranceDb, ...
    RepeatCount=repeatCount);
obj.refresh_all_plots_();
obj.update_runtime_state_();
obj.report_refinement_(r, 'Tone');
end
