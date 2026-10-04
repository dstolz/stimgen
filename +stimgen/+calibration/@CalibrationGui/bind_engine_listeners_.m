function bind_engine_listeners_(obj)
% Follow the current engine's ConductionDelay property. The click
% probes fire during a run, while this window sits in
% with_busy_state_ showing only "Running tone calibration...", so
% without the listener the delay would not be seen until the run
% finished.
delete(obj.DelayListener_);
obj.DelayListener_ = addlistener(obj.Engine, 'ConductionDelay', ...
    'PostSet', @(~,~) obj.refresh_conduction_delay_label_());
% And its RunProgress, for the status line's "Tone 12/40": the
% only sign of life a multi-minute sweep gives with live plots
% off, since the engine publishes it either way.
delete(obj.ProgressListener_);
obj.ProgressListener_ = addlistener(obj.Engine, 'RunProgress', ...
    'PostSet', @(~,~) obj.on_run_progress_());
end
