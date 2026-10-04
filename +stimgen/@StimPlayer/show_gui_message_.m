function show_gui_message_(obj, messageText, titleText, iconName)
% show_gui_message_() - Best-effort wrapper around uialert.
arguments
    obj (1,1) stimgen.StimPlayer
    messageText (1,1) string
    titleText (1,1) string = "StimPlayer"
    iconName (1,1) string = "info"
end

if isempty(obj.hFig) || ~isvalid(obj.hFig)
    return
end

obj.set_status_(titleText + ": " + messageText, isError=iconName == "error");

try
    if any(iconName == ["error", "success"])
        uialert(obj.hFig, char(messageText), char(titleText), 'Icon', char(iconName));
    end
catch
    % Ignore alert failures if the figure is closing.
end
end
