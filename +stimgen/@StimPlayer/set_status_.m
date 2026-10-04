function set_status_(obj, messageText, options)
% set_status_() - Update the non-modal status label in the GUI.
arguments
    obj (1,1) stimgen.StimPlayer
    messageText (1,1) string
    options.isError (1,1) logical = false
end

h = obj.handles;
if ~isfield(h, 'StatusLabel') || isempty(h.StatusLabel) || ~isvalid(h.StatusLabel)
    return
end

h.StatusLabel.Text = char(messageText);
if options.isError
    h.StatusLabel.FontColor = [0.75 0.15 0.15];
else
    h.StatusLabel.FontColor = [0.35 0.35 0.35];
end
end
