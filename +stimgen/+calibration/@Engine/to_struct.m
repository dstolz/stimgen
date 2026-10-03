function s = to_struct(obj)
% s = to_struct(obj)
% The engine's persistent state as a plain struct: what a .esgc file holds
% (Engine.save) and what a calibration embedded in a .spl bank or a
% serialized StimType holds (StimCalibration.toStruct/saveobj). One list, so
% the two cannot drift apart; restore() reads it back.
%
% Returns:
%   s - struct of engine properties, schema version 3

% 2: levels are referenced to 20 uPa alone. Version 1 files added the
% calibrator's ReferenceLevel on top of that, counting it twice, so their
% tables are (ReferenceLevel - 94) dB off -- nothing at the default 94 dB
% calibrator setting, 20 dB on a 114 dB one. load() checks for this and says
% so rather than letting a stale table pass silently. See Engine.volts_to_spl.
% 3: every tone/click/swept_sine table records normative_db, the level its
% voltage column produces. Earlier files have none; restore() stamps their
% tables with the file's own NormativeValue, which is what built them, so a
% version 2 file plays exactly as it did. See Engine.lut_normative_db.
s.version             = 3;
s.CalibrationData     = obj.CalibrationData;
s.MicSensitivity      = obj.MicSensitivity;
s.NormativeValue      = obj.NormativeValue;
s.ReferenceLevel      = obj.ReferenceLevel;
s.ReferenceFrequency  = obj.ReferenceFrequency;
s.ExcitationVoltage   = obj.ExcitationVoltage;
s.MaxOutputVoltage    = obj.MaxOutputVoltage;
% The rig settings the tables were measured through. Nothing reads them back
% into a calculation -- the gain is already inside the voltages -- but a file
% that does not say which knob positions it was taken at cannot be reproduced
% or checked against a later one.
s.AdcGain             = obj.AdcGain;
s.DacAttenuation      = obj.DacAttenuation;
s.ToneLutSource       = obj.ToneLutSource;
s.AcCoupleResponse    = obj.AcCoupleResponse;
s.AcCoupleFrequency   = obj.AcCoupleFrequency;
% The ramp the tables' own bursts were gated with -- refine_tones/test_tones
% replay a table at this shape, so a mismatched ramp would be measuring a
% different burst than the one that built the table.
s.ToneRampDuration    = obj.ToneRampDuration;
% The room the measurement was made in, to the extent this class knows it:
% the reflection distances in a swept-sine analysis were computed at this
% temperature, so reading them back later without it would be reading them
% at whatever the loading rig happens to be set to.
s.AmbientTemperature  = obj.AmbientTemperature;
% How the tables in this file were analysed, not just what they measured: a
% level read with a different window is a different number, so the settings
% travel with the data that was taken under them.
s.SpectralWindow      = obj.SpectralWindow;
s.SpectralFftLength   = obj.SpectralFftLength;
% The operator's own account of this calibration. Everything else in the file
% describes how the measurement was made; this is the only field that can say
% what it was made on, and it is worth nothing if it does not travel with the
% tables it describes.
s.Notes               = obj.Notes;
s.CalibrationTimestamp = obj.CalibrationTimestamp;
end
