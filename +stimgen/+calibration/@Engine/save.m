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

s.version             = 1;
s.CalibrationData     = obj.CalibrationData;
s.MicSensitivity      = obj.MicSensitivity;
s.NormativeValue      = obj.NormativeValue;
s.ReferenceLevel      = obj.ReferenceLevel;
s.ReferenceFrequency  = obj.ReferenceFrequency;
s.ExcitationVoltage   = obj.ExcitationVoltage;
s.MaxOutputVoltage    = obj.MaxOutputVoltage;
s.ToneLutSource       = obj.ToneLutSource;
s.AcCoupleResponse    = obj.AcCoupleResponse;
s.AcCoupleFrequency   = obj.AcCoupleFrequency;
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
s.CalibrationTimestamp = obj.CalibrationTimestamp;

save(ffn, '-struct', 's');
stimgen.util.vprintf(0, 'Saved calibration: "%s"', ffn);
end
