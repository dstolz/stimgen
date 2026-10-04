function on_spectral_setting_changed_(obj)
% Separate from on_hardware_setting_changed_ only because of what
% follows it: the last acquired record is re-analysed and redrawn,
% so the choice is answered on screen rather than at the next
% sweep. Nothing already in a lookup table is recomputed -- those
% numbers are what their own measurement found.
try
    obj.Engine.set_configuration( ...
        SpectralWindow=obj.SpectralWindowDrop.Value, ...
        SpectralFftLength=obj.SpectralFftDrop.Value);
catch ME
    obj.set_status_(sprintf('Parameter update failed: %s', ME.message), true);
    obj.sync_hardware_dialog_();
    return
end

obj.Monitor.show_engine_state(obj.Engine);
obj.set_status_(sprintf( ...
    'Spectral analysis: %s window, %s. Applies to the next measurement.', ...
    stimgen.calibration.SpectralOptions.windowLabel(obj.Engine.SpectralWindow), ...
    stimgen.calibration.SpectralOptions.fftLengthLabel(obj.Engine.SpectralFftLength)), ...
    false);
end
