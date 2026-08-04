function plot_spectrum(obj, reset)
% plot_spectrum(obj)       - draw the spectrum of the current ResponseSignal
% plot_spectrum(obj, true) - clear the monitor's panels
%
% Deprecated; see plot_signal. Both panels come from one snapshot, so this is
% the same call.
%
% See also: stimgen.calibration.LiveMonitor.show_engine_state
arguments
    obj
    reset (1,1) logical = false
end
obj.render_engine_state_(reset);
end
