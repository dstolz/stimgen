function report_gui_error_(obj, ME, titleText, userMessage)
% report_gui_error_() - Log an exception and show a user-facing alert.
arguments
    obj (1,1) stimgen.StimPlayer
    ME (1,1) MException
    titleText (1,1) string = "StimPlayer Error"
    userMessage (1,1) string = "An unexpected error occurred."
end

stimgen.util.vprintf(0, 1, '%s: %s', char(titleText), ME.message);
stimgen.util.vprintf(0, 1, ME);

detailedMessage = obj.format_gui_error_message_(ME, userMessage);
obj.set_status_(titleText + ": " + detailedMessage, isError=true);

if isempty(obj.hFig) || ~isvalid(obj.hFig)
    return
end

try
    uialert(obj.hFig, char(detailedMessage), ...
        char(titleText), 'Icon', 'error');
catch
    % Avoid cascading GUI failures while reporting an error.
end
end
