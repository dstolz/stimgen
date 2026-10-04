function require_hardware_route_(obj)
% require_hardware_route_() - Error unless hardware preview can play.
if ~obj.has_hardware_route_
    error('stimgen:StimPlayer:NoHardwareHost', ...
        ['No hardware host or CaptureAdapter is attached, so only ' ...
        'speaker preview is available.']);
end
end
