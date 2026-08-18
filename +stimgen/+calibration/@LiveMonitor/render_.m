function render_(obj, d)
% render_(obj, d)
% Draw all three panels from one payload. Each panel skips itself when its
% axes were never supplied or have since been deleted.

if isgraphics(obj.AxSignal)
    obj.render_signal_(d);
end
if isgraphics(obj.AxSpectrum)
    obj.render_spectrum_(d);
end

% Below them, the panel the run's own stage belongs to. A delay probe has no
% lookup table and would otherwise leave a sweep panel showing the last
% curve while the measurement it is running has nowhere to be drawn; a
% sweep goes to its stimulus's panel, which where the host gave each one is
% what keeps a click run from painting over a tone table.
if ~isempty(d.Latency.lag_ms)
    if isgraphics(obj.AxLatency)
        obj.render_latency_(d.Latency);
    end
elseif ~isempty(d.Table.x)
    obj.render_transfer_(d, ...
        stimgen.calibration.LiveMonitor.stage_panel(d.Stage));
end
end
