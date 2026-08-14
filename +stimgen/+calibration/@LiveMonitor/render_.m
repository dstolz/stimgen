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

% The transfer panel serves whichever of its views the payload carries data
% for. A delay probe has no lookup table and would otherwise leave the panel
% showing the last sweep's curve while the measurement it is running has
% nowhere to be drawn.
if ~isgraphics(obj.AxTransfer)
    return
end
if ~isempty(d.Latency.lag_ms)
    obj.render_latency_(d.Latency);
elseif ~isempty(d.Table.x)
    obj.render_transfer_(d);
end
end
