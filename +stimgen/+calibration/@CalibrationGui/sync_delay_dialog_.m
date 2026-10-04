function sync_delay_dialog_(obj)
% Same contract as sync_hardware_dialog_: whoever owns a value
% writes the field, never the other way round.
if isempty(obj.DelayDialog_) || ~obj.DelayDialog_.isOpen()
    return
end
obj.DelayMaxField.Value = obj.DelayMaxMs_;
obj.DelayClicksField.Value = obj.DelayNumClicks_;
% Clamped, not just converted: an engine may carry a temperature
% from outside the range this field offers -- a loaded .esgc, or a
% headless script -- and a uieditfield throws on a Value outside
% its own Limits.
obj.AmbientTempField.Value = min(max( ...
    obj.Engine.AmbientTemperature, ...
    obj.AmbientTempField.Limits(1)), obj.AmbientTempField.Limits(2));
end
