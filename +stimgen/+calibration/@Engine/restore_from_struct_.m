function restore_from_struct_(obj, s)
% restore_from_struct_(obj, s)
% Populate engine properties from a saved .esgc struct.
obj.CalibrationData      = s.CalibrationData;
obj.MicSensitivity       = s.MicSensitivity;
obj.NormativeValue       = s.NormativeValue;
obj.ReferenceLevel       = s.ReferenceLevel;
obj.ReferenceFrequency   = s.ReferenceFrequency;
obj.ExcitationVoltage    = s.ExcitationVoltage;
if isfield(s, 'OnsetIgnoreDuration')
    obj.OnsetIgnoreDuration = s.OnsetIgnoreDuration;
end
obj.CalibrationTimestamp = s.CalibrationTimestamp;
end
