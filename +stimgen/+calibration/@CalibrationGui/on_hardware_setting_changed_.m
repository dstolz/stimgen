function on_hardware_setting_changed_(obj)
try
    obj.Engine.set_configuration( ...
        MaxOutputVoltage=obj.MaxOutputField.Value, ...
        AcCoupleResponse=obj.AcCoupleCheck.Value, ...
        AdcGain=obj.AdcGainField.Value, ...
        DacAttenuation=obj.DacAttenField.Value);
    obj.set_status_('Hardware settings applied.', false);
catch ME
    obj.set_status_(sprintf('Parameter update failed: %s', ME.message), true);
    % Put the rejected control back to what the engine holds.
    obj.sync_hardware_dialog_();
end
end
