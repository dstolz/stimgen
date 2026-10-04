function on_print_summary_(obj)
% Print the calibration's own description to the command window.
% Notes are committed first so what is printed includes a note
% still being typed, and the command window is raised because
% this window is usually covering it.
obj.commit_notes_();
obj.Engine.describe();
try
    commandwindow;
catch ME
    % No desktop (-nodesktop, or a headless run). The text was
    % printed either way, which is the part that matters.
    stimgen.util.vprintf(2, ME);
end
obj.set_status_('Calibration summary printed to the command window.', false);
end
