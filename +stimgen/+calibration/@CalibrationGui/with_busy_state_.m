function with_busy_state_(obj, fcn, busyMessage, cancellable)
arguments
    obj
    fcn
    busyMessage
    cancellable (1,1) logical = false
end
% The menus are not disabled while a run is in progress, so Load,
% Save and the runtime items can arrive here mid-run (the engine
% pumps the event queue between measurements). Running one inside
% another would interleave two engine runs; refuse instead.
if obj.Busy_
    obj.set_status_(['Another operation is still running. Wait for it ' ...
        'to finish, or press Stop.'], true);
    return
end
obj.Busy_ = true;
obj.BusyMessage_ = char(busyMessage);

% What the run is judged against for Dirty_: the engine it started
% on, its data revision, and the sensitivity (which is saved in the
% file but is not CalibrationData).
engBefore  = obj.Engine;
revBefore  = engBefore.DataRevision;
sensBefore = engBefore.MicSensitivity;

obj.set_status_(busyMessage, false);
obj.Figure.Pointer = 'watch';
obj.set_busy_(true, cancellable);
drawnow;
try
    if cancellable
        % One cancel scope for the whole action, so a Stop that
        % lands between its runs (a sweep and its refinement)
        % is not cleared by the next run's entry.
        obj.Engine.run_cancellable(fcn);
    else
        fcn();
    end
catch ME
    if ~obj.ui_alive_()
        % The figure went mid-run (close all force); the error
        % is most likely the run writing to it. There is nothing
        % left to show it on, so it goes to the log.
        stimgen.util.vprintf(0, 1, ME);
    elseif isequal(ME.identifier, 'stimgen:calibration:Engine:cancelled')
        obj.set_status_('Calibration cancelled.', false);
    else
        obj.set_status_(ME.message, true);
        uialert(obj.Figure, ME.message, 'Calibration Error', Icon='error');
    end
end
if ~isvalid(obj)
    return
end
obj.Busy_ = false;

% A load swaps the engine and clears Dirty_ itself; a save clears
% it and changes nothing. Anything else that moved the data, on
% an engine that has something to save, has left it unsaved.
if obj.Engine == engBefore && obj.Engine.IsCalibrated && ...
        (obj.Engine.DataRevision ~= revBefore || ...
         obj.Engine.MicSensitivity ~= sensBefore)
    obj.Dirty_ = true;
end

if obj.ui_alive_()
    obj.Figure.Pointer = 'arrow';
    obj.set_busy_(false, false);
    obj.update_runtime_state_();
    drawnow;
end

% A close asked for mid-run, now that the run has stopped. Through
% on_close_ again, so an unsaved calibration is still offered a
% save; cancelling that leaves the window open and idle.
if obj.CloseRequested_
    obj.CloseRequested_ = false;
    if obj.ui_alive_()
        obj.on_close_(obj.Figure);
    end
end
end
