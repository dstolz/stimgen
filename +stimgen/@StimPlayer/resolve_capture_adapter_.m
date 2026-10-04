function adapter = resolve_capture_adapter_(obj)
% adapter = resolve_capture_adapter_() - The hardware capture_stim records through.
% CaptureAdapter when one is set (calling it when it is a
% function), else the host's calibration adapter -- the same one
% hardware preview uses, connected on demand. Errors when there
% is neither, since a capture through nothing is not a capture.
adapter = obj.CaptureAdapter;
if isa(adapter, 'function_handle')
    adapter = adapter();
    if ~(isa(adapter, 'stimgen.calibration.HwAdapter') && isscalar(adapter))
        error('stimgen:StimPlayer:BadCaptureAdapter', ...
            ['The CaptureAdapter function returned a %s, not a ' ...
             'stimgen.calibration.HwAdapter.'], class(adapter));
    end
end
if ~isempty(adapter)
    return
end
if ~isempty(obj.Host)
    adapter = obj.resolve_preview_adapter_;
    return
end
error('stimgen:StimPlayer:NoCaptureHardware', ...
    ['No capture hardware: set CaptureAdapter to a ' ...
     'stimgen.calibration.HwAdapter (or a function returning one), ' ...
     'or open StimPlayer from a host that supplies a calibration adapter.']);
end
