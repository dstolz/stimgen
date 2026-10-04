function tf = stim_has_calibration_(~, stimObj)
% tf = stim_has_calibration_(stimObj) - True when the stimulus
% carries usable calibration data that it is set to apply.
C  = stimObj.Calibration;
tf = stimObj.ApplyCalibration && ...
    isa(C, 'stimgen.StimCalibration') && ~isempty(C.CalibrationData);
end
