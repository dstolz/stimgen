function plot_signal(obj, reset)
% plot_signal(obj)       - draw the current ResponseSignal
% plot_signal(obj, true) - clear the monitor's panels
%
% Deprecated. The engine no longer draws: it broadcasts LiveUpdate and
% stimgen.calibration.LiveMonitor renders. This entry point is kept so scripts
% written against the old subplot figure keep working, and forwards to whatever
% monitors are attached -- creating one that owns its own window if none is.
%
% The waveform and spectrum panels are refreshed together, because both come
% from the one snapshot the monitor is handed. Prefer attaching a LiveMonitor
% and calling its show_engine_state directly.
%
% See also: stimgen.calibration.LiveMonitor.show_engine_state
arguments
    obj
    reset (1,1) logical = false
end
obj.render_engine_state_(reset);
end
