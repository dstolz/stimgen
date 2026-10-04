function on_run_progress_(obj)
% Append the engine's progress to the running action's status
% line. Only while an action is running -- a script driving the
% same engine outside this window has its own console -- and not
% once a close is pending, whose message has to stay readable.
if ~obj.Busy_ || obj.CloseRequested_ || ~obj.ui_alive_()
    return
end
txt = progress_text_(obj.Engine.RunProgress);
if strlength(txt) > 0
    obj.set_status_(sprintf('%s  %s', obj.BusyMessage_, txt), false);
end
end
