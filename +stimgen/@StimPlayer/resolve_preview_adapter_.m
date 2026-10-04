function adapter = resolve_preview_adapter_(obj)
% adapter = resolve_preview_adapter_() - Hardware route for preview.
% Returns the cached stimgen.calibration.HwAdapter, building one
% from the host when needed. If the host has a protocol loaded
% but nothing connected yet, it is connected and put in Preview
% mode first — the same steps a Run performs.
%
% Errors (with the host's own diagnostic) when no interface
% exposes the calibration playback tags.
%
% With no host, the route is CaptureAdapter -- resolved afresh
% each time and never cached here, since a function handle is
% there precisely so the adapter follows the application's
% current device settings.

if isempty(obj.Host)
    obj.require_hardware_route_;
    adapter = obj.resolve_capture_adapter_;
    return
end

if ~isempty(obj.PreviewAdapter_) && isvalid(obj.PreviewAdapter_)
    adapter = obj.PreviewAdapter_;
    return
end

try
    adapter = obj.Host.calibrationAdapter();
catch firstME
    if obj.Host.hasProtocol() && obj.Host.connectionState() == "None"
        obj.Host.connect();
        obj.Host.setMode("Preview");
        obj.update_protocol_status_;
        adapter = obj.Host.calibrationAdapter();
    else
        rethrow(firstME);
    end
end

obj.PreviewAdapter_ = adapter;
end
