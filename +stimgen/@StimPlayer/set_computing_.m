function set_computing_(obj, tf)
% set_computing_(obj, tf) - Toggle the "Computing" activity lamp.
% Forces an immediate redraw so the lamp is visible before a blocking
% signal-generation call starts, and is cleared again once it returns.

h = obj.handles;
if ~isfield(h, 'ComputingLamp') || isempty(h.ComputingLamp) || ~isvalid(h.ComputingLamp)
    return
end

if tf
    h.ComputingLamp.Color = [0.95 0.75 0.10];
else
    h.ComputingLamp.Color = [0.75 0.75 0.75];
end
drawnow;
end
