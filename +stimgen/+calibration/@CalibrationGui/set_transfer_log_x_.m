function set_transfer_log_x_(obj, tf)
% Log or linear frequency on every frequency panel.
obj.Monitor.LogX = tf;
obj.sync_display_controls_();
obj.redraw_transfer_panels_();
end
