function reason = hardware_unavailable_reason_(obj)
% reason = hardware_unavailable_reason_() - Why a Run would have no hardware output.
% "" when HardwareAvailable is true or no host is attached.
reason = "";
if isempty(obj.Host) || obj.HardwareAvailable
    return
end
if ~obj.Host.hasProtocol()
    reason = "No protocol is loaded, so no hardware is connected.";
elseif obj.Host.connectionState() == "None"
    reason = "The hardware is not connected.";
else
    missing = string(obj.RequiredParams_(~isfield(obj.PARAMS, obj.RequiredParams_)));
    reason = "The loaded circuit does not expose these parameters: " + ...
        strjoin(missing, ", ") + ".";
end
end
