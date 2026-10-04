function initialize_runtime_from_protocol_(obj)
% initialize_runtime_from_protocol_() - Connect host hardware for playback.

obj.disconnect_interfaces_;

if isempty(obj.Host) || ~obj.Host.hasProtocol()
    return
end

obj.Host.connect();
obj.Host.setMode("Preview");
end
