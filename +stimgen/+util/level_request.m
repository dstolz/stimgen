function req = level_request(stimObj)
% req = stimgen.util.level_request(stimObj)
% What level a stimulus asks for, and how that level has to be measured.
%
% A calibrated stimulus asks for its Sound Level in dB SPL, and the table that
% scaled it was built from one particular measurement. Checking the level that
% comes back means measuring it the SAME way:
%
%   tone                     spectral rms at the tone frequency -- the tone
%                            LUT is built from exactly that estimate
%   click                    peak, as an rms equivalent -- the click LUT is
%                            built from a peak, and a click train is mostly
%                            silence, so an rms would read tens of dB low
%   LevelReference = "peak"  the same, for a stimulus that scales its peak
%                            (stimgen.SoundFile) rather than its rms
%   everything else          broadband rms -- noise, TORC, a swept sine
%                            spreads its energy over the whole span, sound
%                            files, and anything with no single frequency to
%                            anchor to
%
% Measuring a tone with a broadband rms instead folds the room noise into the
% number and reads as a calibration error of a decibel or two that is not
% there. This is the half of the rule that reads the stimulus;
% stimgen.util.level_as_calibrated is the half that reads the recording. They
% were one local function in stimgen.SpotCheck until StimPlayer's capture
% needed the same answer, and sharing them is what keeps a spot check and a
% capture from disagreeing about how a level is measured.
%
% Values come from StimType.active_variant_values, so a vectorized stimulus
% reports the combination that produced its current Signal without advancing
% the selection. selected_value could not be used: outside a variant cycle it
% reselects, and asking would change the answer.
%
% Parameters:
%   stimObj - stimgen.StimType that was (or is about to be) played
%
% Returns:
%   req - struct:
%     class                (1,1) string, the stimulus class
%     calibration_type     (1,1) string, its CalibrationType
%     level_db             requested Sound Level (dB SPL when calibrated);
%                          NaN when it has none
%     mode                 "specfreq" | "peak" | "rms" -- how to measure it
%     frequency_hz         anchor frequency for "specfreq"; NaN otherwise.
%                          Not yet checked against a sample rate:
%                          level_as_calibrated falls back to broadband rms
%                          for an anchor at or above Nyquist, and says so.
%     applies_calibration  ApplyCalibration
%     has_calibration_data a stimgen.StimCalibration with tables is attached
%     calibrated           both: the requested level is a real dB SPL rather
%                          than a nominal one
%     variant              struct from active_variant_values
%
% Example:
%   req = stimgen.util.level_request(toneObj);
%   m   = stimgen.util.level_as_calibrated(micRecord, fs, req, micSensitivity);
%
% See also: stimgen.util.level_as_calibrated, stimgen.SpotCheck,
%           stimgen.StimPlayer.capture_stim
arguments
    stimObj (1,1) stimgen.StimType
end

variant = stimObj.active_variant_values();
calType = string(stimObj.CalibrationType);

levelDb = scalar_(active_value_(stimObj, "SoundLevel", variant));

anchorHz = nan;
switch calType
    case "tone"
        mode     = "specfreq";
        anchorHz = scalar_(active_value_(stimObj, "Frequency", variant));
    case "click"
        mode = "peak";
    otherwise
        mode = "rms";
end

% A stimulus that scales its peak asks for a peak level, whatever its table.
if mode == "rms" && isprop(stimObj, 'LevelReference') ...
        && string(stimObj.LevelReference) == "peak"
    mode = "peak";
end

if mode == "specfreq" && ~(isfinite(anchorHz) && anchorHz > 0)
    % An unusable anchor would make spectral_rms measure an arbitrary bin.
    mode     = "rms";
    anchorHz = nan;
end

hasData = false;
try
    C = stimObj.Calibration;
    hasData = isa(C, 'stimgen.StimCalibration') ...
        && isstruct(C.CalibrationData) && ~isempty(C.CalibrationData);
catch
end
applies = logical(stimObj.ApplyCalibration);

req = struct( ...
    'class',                string(class(stimObj)), ...
    'calibration_type',     calType, ...
    'level_db',             levelDb, ...
    'mode',                 mode, ...
    'frequency_hz',         anchorHz, ...
    'applies_calibration',  applies, ...
    'has_calibration_data', hasData, ...
    'calibrated',           applies && hasData, ...
    'variant',              variant);
end


% ------------------------------------------------------------------------ %
function v = active_value_(stimObj, propName, variant)
% One property's value for the active variant, without advancing the cycle.
% Scalar properties are returned as they are; vectorized ones come from the
% combination table active_variant_values already resolved.
name = char(propName);
if ~isprop(stimObj, name)
    v = nan;
    return
end

raw = stimObj.(name);
if numel(raw) <= 1
    v = raw;
elseif isstruct(variant) && isfield(variant, name)
    v = variant.(name);
else
    v = raw(1);
end
end


function v = scalar_(v)
% A finite numeric scalar, or NaN.
if ~(isnumeric(v) || islogical(v)) || ~isscalar(v) || ~isfinite(double(v))
    v = nan;
else
    v = double(v);
end
end
