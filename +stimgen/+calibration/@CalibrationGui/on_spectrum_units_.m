function on_spectrum_units_(obj, src)
% Redraw the spectrum panel in the selected unit. The record is
% kept in volts by the monitor, so this costs a redraw of what is
% already measured -- nothing has to be re-acquired.
obj.Monitor.SpectrumUnits = src.UserData;
obj.sync_spectrum_units_menu_();
obj.Monitor.show_engine_state(obj.Engine);
obj.set_status_(sprintf('Spectrum in %s.', src.UserData), false);
end
