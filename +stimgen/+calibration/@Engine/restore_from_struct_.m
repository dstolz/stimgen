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

% Written since acquisition could be AC-coupled; an older file keeps the
% default, which is the behavior it was measured under. DemeanResponse is the
% option AC coupling replaced -- it named the same intent (block the input
% stage's DC) by the weaker means, so a file carrying it restores as AC
% coupling at the current default corner rather than as "off".
if isfield(s, 'AcCoupleResponse')
    obj.AcCoupleResponse = s.AcCoupleResponse;
elseif isfield(s, 'DemeanResponse')
    obj.AcCoupleResponse = s.DemeanResponse;
end

if isfield(s, 'AcCoupleFrequency')
    obj.AcCoupleFrequency = s.AcCoupleFrequency;
end
end
