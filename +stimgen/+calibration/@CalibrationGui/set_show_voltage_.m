function set_show_voltage_(obj, tf)
% Right-hand drive-voltage axis on the transfer panel.
obj.Monitor.ShowVoltage = tf;
obj.sync_display_controls_();
obj.redraw_transfer_panels_();
end
