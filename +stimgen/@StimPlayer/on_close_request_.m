function on_close_request_(obj)
% on_close_request_() - Figure CloseRequestFcn: confirm before losing work.
% A running (or paused) session is stopped by closing and the
% presentation log in memory goes with the player, so that is
% confirmed first; then unsaved bank edits are offered for saving. A
% failure while asking must not leave a window that cannot be
% closed, so it is logged and the window closes.
try
    if ~isempty(obj.Timer) && isvalid(obj.Timer) && strcmp(obj.Timer.Running, 'on')
        % A hardware run's log is written as the timer stops
        % (autosave_presentation_log_); anything else goes with the player.
        if obj.HardwareRun_ && strlength(obj.PresentationLogDir) > 0
            fate = sprintf(['its presentation log is saved to %s as it stops, ' ...
                'and the copy in memory goes with the player.'], char(obj.PresentationLogDir));
        else
            fate = ['its presentation log (StimOrder, StimOrderTime, StimPolarity, ' ...
                'StimVariant, StimLateness, StimRecord) is discarded with the player.'];
        end
        msg = sprintf('A session is running (%d of %d presentations made). Closing stops it, and %s', ...
            obj.presented_count_(), obj.total_count_(), fate);
        choice = uiconfirm(obj.hFig, msg, 'Close StimPlayer', ...
            'Options', {'Stop and Close', 'Cancel'}, ...
            'DefaultOption', 2, 'CancelOption', 2, 'Icon', 'warning');
        if ~strcmp(choice, 'Stop and Close')
            return
        end
    end
    if ~obj.confirm_discard_changes_("closing")
        return
    end
catch ME
    stimgen.util.vprintf(0, 1, 'StimPlayer: close confirmation failed; closing anyway.');
    stimgen.util.vprintf(0, 1, ME);
end
if ~isempty(obj.hFig) && isvalid(obj.hFig)
    delete(obj.hFig);  % DeleteFcn deletes the player
end
end
