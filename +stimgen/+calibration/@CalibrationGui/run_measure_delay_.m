function run_measure_delay_(obj)
% Probe the rig for its conduction delay on its own, outside any
% sweep. A tone run measures the same thing per acquisition and
% consumes it; here nothing consumes it, so the result is reported
% in a dialog rather than left as a number in the footer -- what
% this button is for is reading the delay and the distance it
% implies, and both are worth stating with the evidence behind
% them.
%
% The parameters are taken from Options > Conduction Delay
% Settings... rather than asked for here: pressing Measure runs the
% measurement.
maxDelayMs = obj.DelayMaxMs_;
[d, diag] = obj.Engine.measure_conduction_delay( ...
    MaxDelay=maxDelayMs / 1e3, NumClicks=obj.DelayNumClicks_);

% The probe record and the correlation read off it are the
% evidence for the reading, and with live plots off nothing has
% drawn either. Shown before the alert, so both are already on
% screen behind the numbers -- and drawn from the returned
% diagnostics rather than from the live stream, so the panel does
% not depend on a display toggle that has nothing to do with this
% measurement.
obj.LastLatency_ = diag;
obj.Monitor.show_engine_state(obj.Engine);
obj.Monitor.show_latency(diag);
obj.set_transfer_view_("latency");
drawnow;

obj.set_status_(stimgen.calibration.Engine.conduction_delay_summary(d), ~d.valid);

if d.valid
    icon = 'info';
else
    icon = 'warning';
end
uialert(obj.Figure, stimgen.calibration.Engine.conduction_delay_report(d, maxDelayMs), ...
    'Conduction Delay', Icon=icon);
end
