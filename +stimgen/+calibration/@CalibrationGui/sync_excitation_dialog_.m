function sync_excitation_dialog_(obj)
% Same contract as sync_hardware_dialog_: the engine owns these
% values, the window is only a view of them.
if isempty(obj.ExcitationDialog_) || ~obj.ExcitationDialog_.isOpen()
    return
end
obj.ExcitationField.Value = obj.Engine.ExcitationVoltage;
obj.ToneRampField.Value = obj.Engine.ToneRampDuration * 1000;
end
