function tf = has_hardware_route_(obj)
% tf = has_hardware_route_() - True when hardware preview can play:
% an attached host, or a CaptureAdapter to play through instead.
tf = ~isempty(obj.Host) || ~isempty(obj.CaptureAdapter);
end
