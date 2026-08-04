function refresh_plots(obj)
% refresh_plots(obj)
% Redraw all three panels from the Engine's current state.
%
% Used after a run finishes, after a .esgc file is loaded, and from the toolbar.
% During a run the panels are driven by the LiveUpdate event instead; this is
% the off-run equivalent.
%
% Order matters: show_calibration resets the monitor's graphics cache before
% drawing the lookup tables, so the response panels have to be drawn after it,
% not before.

if isempty(obj.Monitor) || ~isvalid(obj.Monitor)
    return
end

obj.Monitor.show_calibration(obj.Engine);
obj.Monitor.show_engine_state(obj.Engine);
end
