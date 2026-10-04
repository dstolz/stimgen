function on_ambient_temp_changed_(obj)
% Its own handler rather than on_hardware_setting_changed_: that
% one reads controls on the other settings window, which may not
% be open.
try
    obj.Engine.set_configuration( ...
        AmbientTemperature=obj.AmbientTempField.Value);
    obj.set_status_('Ambient temperature applied.', false);
catch ME
    obj.set_status_(sprintf('Parameter update failed: %s', ME.message), true);
    obj.sync_delay_dialog_();
end
end
