function sync_hardware_dialog_(obj)
% The engine owns these settings; the window, when open, is only
% a view of them. Called wherever the engine may have changed
% under the window -- construction, load, engine swap.
if isempty(obj.HardwareDialog_) || ~obj.HardwareDialog_.isOpen()
    return
end
obj.MaxOutputField.Value = obj.Engine.MaxOutputVoltage;
obj.AcCoupleCheck.Value = obj.Engine.AcCoupleResponse;
obj.AdcGainField.Value = obj.Engine.AdcGain;
obj.DacAttenField.Value = obj.Engine.DacAttenuation;
obj.SpectralWindowDrop.Value = obj.Engine.SpectralWindow;
% A loaded calibration may name a length this list does not offer,
% having been saved from a hand-configured engine. Show it rather
% than silently snapping the engine to a neighbouring value.
set_dropdown_value_(obj.SpectralFftDrop, obj.Engine.SpectralFftLength, ...
    @stimgen.calibration.SpectralOptions.fftLengthLabel);
end
