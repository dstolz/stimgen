function restore_from_struct_(obj, s)
% restore_from_struct_(obj, s)
% Populate engine properties from a saved .esgc struct.
obj.CalibrationData      = s.CalibrationData;
obj.MicSensitivity       = s.MicSensitivity;
obj.NormativeValue       = s.NormativeValue;
obj.ReferenceLevel       = s.ReferenceLevel;
obj.ReferenceFrequency   = s.ReferenceFrequency;
obj.ExcitationVoltage    = s.ExcitationVoltage;
obj.CalibrationTimestamp = s.CalibrationTimestamp;

% Written since the output ceiling became configurable; a file saved before
% that keeps the property's default rather than failing to load.
if isfield(s, 'MaxOutputVoltage')
    obj.MaxOutputVoltage = s.MaxOutputVoltage;
end

% Written since tone lookups could be redirected to the swept sine LUT; an
% older file keeps the default direct-tone source.
if isfield(s, 'ToneLutSource')
    obj.ToneLutSource = s.ToneLutSource;
end

% Written since acquisition could be demeaned; an older file keeps the
% default, which is the behavior it was measured under.
if isfield(s, 'DemeanResponse')
    obj.DemeanResponse = s.DemeanResponse;
end
end
