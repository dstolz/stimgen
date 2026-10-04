function redraw_transfer_panels_(obj)
% Redraw every measurement panel: the three stimulus tabs and
% their detail axes, the filter test, the background analysis,
% the delay probe.
% They own separate axes and no longer clear each other, so there
% is no view to choose between and no ordering to respect -- this
% is what a display option that applies to every panel (the log
% x-axis, the drive voltage axis, a weighting overlay) calls to
% make the change show on the panels that are not on top as well
% as the one that is.
obj.Monitor.show_calibration(obj.Engine);
obj.Monitor.show_filter_test(obj.Engine);
obj.Monitor.show_background(obj.Engine);
obj.Monitor.show_latency(obj.LastLatency_);
end
