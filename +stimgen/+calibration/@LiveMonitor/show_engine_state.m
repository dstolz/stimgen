function show_engine_state(obj, eng)
% show_engine_state(obj, eng)
% Draw the engine's current ResponseSignal on the waveform and spectrum
% panels, outside a run. Used by a host GUI to refresh those panels after a
% load, and by the Engine's legacy plot_signal/plot_spectrum entry points, so
% the off-run view is the same rendering as the live one rather than a second
% implementation that drifts from it.
%
% Parameters:
%   eng - stimgen.calibration.Engine
arguments
    obj
    eng (1,1) stimgen.calibration.Engine
end

d = eng.live_snapshot_("manual", "done");
if isgraphics(obj.AxSignal)
    obj.render_signal_(d);
end
if isgraphics(obj.AxSpectrum)
    obj.render_spectrum_(d);
end
drawnow limitrate;
end
