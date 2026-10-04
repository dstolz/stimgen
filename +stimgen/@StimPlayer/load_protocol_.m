function load_protocol_(obj, protocolInput)
% load_protocol_(obj) - Prompt for a protocol file and load it.
% load_protocol_(obj, protocolInput) - Load a protocol object or file.
% Protocol handling is delegated entirely to the attached host.

if ~isempty(obj.Timer) && isvalid(obj.Timer) && strcmp(obj.Timer.Running, 'on')
    obj.show_gui_message_("Stop playback before loading a new protocol.", ...
        "Protocol In Use", "warning");
    return
end

if isempty(obj.Host)
    obj.show_gui_message_("No hardware host is attached; speaker preview only.", ...
        "No Hardware Host", "warning");
    return
end

if nargin < 2 || isempty(protocolInput)
    [fn, pn] = uigetfile({'*.eprot;*.prot;*.json', 'Protocol files (*.eprot,*.prot,*.json)'}, ...
        'Load Protocol', obj.DataPath);
    if isequal(fn, 0)
        return
    end
    protocolInput = fullfile(pn, fn);
elseif (ischar(protocolInput) || isstring(protocolInput)) && ~isfile(protocolInput)
    % A remembered path whose file has since moved or been deleted.
    obj.forget_recent_protocol_(protocolInput);
    obj.set_status_("Protocol file not found: " + string(protocolInput), isError=true);
    return
end

obj.disconnect_interfaces_;

try
    obj.Host.loadProtocol(protocolInput);

    % Track the containing folder so later file dialogs open there.
    if (ischar(protocolInput) || isstring(protocolInput)) && isfile(protocolInput)
        obj.DataPath = string(fileparts(char(protocolInput)));
        obj.remember_recent_protocol_(protocolInput);
    end

    obj.set_status_("Protocol loaded.");
catch ME
    obj.report_gui_error_(ME, "Load Protocol Error", ...
        "StimPlayer could not load the selected protocol.");
end

obj.update_protocol_status_;
end
