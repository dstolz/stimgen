function ffn = save(obj, ffn)
% obj.save()
% ffn = obj.save()
% obj.save(ffn)
% Save calibration to a .esgc file.
%
% Parameters:
%   ffn - full file path (char, optional); prompts if omitted
%
% Returns:
%   ffn - resolved file path; empty if the save dialog was cancelled
arguments
    obj
    ffn (1,:) char = ''
end
if ~obj.IsCalibrated
    error('stimgen:calibration:Engine:notCalibrated', ...
        'Nothing to save - calibration has not been run.');
end
if isempty(ffn)
    pn = getpref('StimCalibration', 'path', pwd);
    [fn, pn] = uiputfile( ...
        {'*.esgc','EPsych Stim Calibration (*.esgc)'}, ...
        'Save Calibration', pn);
    if isequal(fn, 0), return; end
    ffn = fullfile(pn, fn);
    setpref('StimCalibration', 'path', pn);
end
[~, ~, ext] = fileparts(ffn);
if ~strcmpi(ext, '.esgc')
    ffn = [ffn '.esgc'];
end

% 2: levels are referenced to 20 uPa alone. Version 1 files added the
% calibrator's ReferenceLevel on top of that, counting it twice, so their
% tables are (ReferenceLevel - 94) dB off -- nothing at the default 94 dB
% calibrator setting, 20 dB on a 114 dB one. load() checks for this and says
% so rather than letting a stale table pass silently. See Engine.volts_to_spl.
s.version             = 2;
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

save(ffn, '-struct', 's');
stimgen.util.vprintf(0, 'Saved calibration: "%s"', ffn);
end
