function on_close_(obj, fig)
% Mid-run, the window cannot simply go: the engine would keep
% driving the speaker through the rest of the sweep, and every
% line after it in the run would write to deleted handles. Ask the
% engine to stop instead, and leave the close to with_busy_state_,
% which calls back here once the run has unwound. A second press
% while it unwinds only repeats the request.
if obj.Busy_
    obj.CloseRequested_ = true;
    obj.Engine.cancel();
    obj.set_status_('Stopping; the window closes when the run has stopped.', false);
    return
end

if ~obj.confirm_discard_('closing')
    obj.set_status_('Close cancelled.', false);
    return
end

% Settings are snapshotted before anything is torn down: the
% monitor still holds the display state being saved.
obj.save_settings_prefs_();
% Release the monitor before the axes it draws into are deleted.
% The engine may outlive this window -- it might be shared with a
% host application -- and must not keep notifying a renderer whose
% axes died with the figure.
if ~isempty(obj.Monitor) && isvalid(obj.Monitor)
    obj.Monitor.detach();
    delete(obj.Monitor);
end
% The settings windows are satellites of this one and have
% no reason to outlive it.
for dlg = {obj.HardwareDialog_, obj.DelayDialog_, obj.ExcitationDialog_}
    if ~isempty(dlg{1}) && isvalid(dlg{1})
        dlg{1}.close();
    end
end
delete(fig);
end
