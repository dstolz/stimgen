function update_protocol_status_(obj)
% update_protocol_status_() - Refresh protocol/hardware status label.

h = obj.handles;
if ~isfield(h, 'ProtocolStatusLabel') || isempty(h.ProtocolStatusLabel) || ~isvalid(h.ProtocolStatusLabel)
    return
end

if isempty(obj.Host) || ~obj.Host.hasProtocol()
    if isempty(obj.Host) && ~isempty(obj.CaptureAdapter)
        h.ProtocolStatusLabel.Text = 'Protocol: none | HW: capture adapter';
    else
        h.ProtocolStatusLabel.Text = 'Protocol: none | HW: speaker preview only';
    end
    return
end

switch obj.Host.connectionState()
    case "Ready",    hwState = "Ready";
    case "Partial",  hwState = "Partial";
    otherwise,       hwState = "Not Connected";
end

h.ProtocolStatusLabel.Text = sprintf('Protocol: %s | HW: %s', ...
    obj.Host.protocolName(), hwState);
end
