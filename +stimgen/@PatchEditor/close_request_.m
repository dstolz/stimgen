function close_request_(obj)
% close_request_(obj)
% Close the editor and release the modal wait.
%
% Edits were applied to the patch as they were made, so there is nothing to
% commit here. Releasing uiwait lets Patch.edit_graph return, which in turn
% lets StimPlayer's run_action_ rebuild its parameter panel around the new
% node set.

obj.closing = true;
obj.Patch.stop_playback();

if ~isempty(obj.fig) && isvalid(obj.fig)
    obj.fig.WindowButtonDownFcn   = [];
    obj.fig.WindowButtonMotionFcn = [];
    obj.fig.WindowButtonUpFcn     = [];
    uiresume(obj.fig);
    delete(obj.fig);
end
end
