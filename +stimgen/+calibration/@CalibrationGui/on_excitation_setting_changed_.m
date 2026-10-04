function on_excitation_setting_changed_(obj)
try
    obj.Engine.set_configuration( ...
        ExcitationVoltage=obj.ExcitationField.Value, ...
        ToneRampDuration=obj.ToneRampField.Value / 1000);
    obj.set_status_('Excitation settings applied.', false);
catch ME
    obj.set_status_(sprintf('Parameter update failed: %s', ME.message), true);
    obj.sync_excitation_dialog_();
end
end
