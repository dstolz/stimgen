function require_hardware_host_(obj)
% require_hardware_host_() - Error unless a hardware host is attached.
if isempty(obj.Host)
    error('stimgen:StimPlayer:NoHardwareHost', ...
        ['No hardware host is attached, so only speaker preview ' ...
        'is available.']);
end
end
