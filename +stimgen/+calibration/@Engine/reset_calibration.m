function reset_calibration(obj)
% reset_calibration(obj)
% Discard acquired calibration results and start over, without disturbing
% anything the user configured to get here: the attached Adapter, and every
% persistent parameter (MicSensitivity -- including one set by
% calibrate_reference -- ReferenceLevel, ReferenceFrequency, NormativeValue,
% ExcitationVoltage, MaxOutputVoltage, DemeanResponse, ShowLivePlots,
% ToneLutSource) are left
% untouched.
%
% Clears CalibrationData (tone/click/swept_sine tables, any designed filter,
% and any background capture), the last excitation/response record, and
% CalibrationTimestamp, so IsCalibrated becomes false again.

obj.CalibrationData       = [];
obj.ExcitationSignal      = [];
obj.ResponseSignal        = [];
obj.ResponseTHD           = nan;
obj.CalibrationTimestamp  = datetime("");
end
