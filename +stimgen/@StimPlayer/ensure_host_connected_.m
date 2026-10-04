function ensure_host_connected_(obj)
% ensure_host_connected_() - Connect a loaded-but-idle host.
% The same steps a Run performs: connect the interfaces and put
% them in Preview mode. No-op without a protocol or when
% already connected.
if obj.Host.hasProtocol() && obj.Host.connectionState() == "None"
    obj.Host.connect();
    obj.Host.setMode("Preview");
    obj.update_protocol_status_;
end
end
