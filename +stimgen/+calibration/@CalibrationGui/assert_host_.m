function assert_host_(obj)
% Guard the hardware-backed menu actions; offline mode has no host.
if isempty(obj.Host)
    error('stimgen:calibration:CalibrationGui:noHost', ...
        ['No hardware host is attached. Construct CalibrationGui with a ' ...
        'stimgen.HardwareHost, or supply an Engine that already has an adapter.']);
end
end
