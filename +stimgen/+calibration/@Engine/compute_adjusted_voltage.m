function v = compute_adjusted_voltage(obj, type, value, level)
% v = compute_adjusted_voltage(obj, type, value, level)
% Interpolate the calibration LUT and scale to the requested level.
%
% "tone" lookups (and the "filter" lookups anchored to them) are served by
% the LUT that ToneLutSource selects: the direct tone calibration by default,
% or the swept sine calibration when ToneLutSource = "swept_sine" and swept
% sine data exists -- both are on the same SPL/voltage scale. That override
% takes precedence over any direct tone calibration for as long as it is
% set; when no swept sine data exists the direct tone LUT applies as usual.
%
% The voltage column of a table is the drive that produced the table's own
% normative_db, recorded when the sweep committed it -- not the engine's
% NormativeValue now. NormativeValue is a setting for the NEXT sweep, and a
% GUI pushes its field into the engine before every action; scaling a stored
% voltage from the live value would shift every drive by however far the
% field had moved since the sweep. A table restored from a file written
% before the field existed is stamped with that file's NormativeValue by
% restore(), so every table carries one by the time it gets here.
%
% Parameters:
%   type  - "tone" | "click" | "swept_sine" | "filter" | "noise"
%   value - frequency (Hz) for "tone", "swept_sine", "filter", "noise";
%           duration (s) for "click". For "filter"/"noise", if value
%           is NaN/non-positive, ReferenceFrequency is used.
%   level - target sound level in dB SPL
%
% Returns:
%   v - required output voltage (double)
if ~obj.IsCalibrated
    error('stimgen:calibration:Engine:notCalibrated', ...
        'No calibration data available. Run calibration or load a .esgc file.');
end

type = lower(string(type));
if type == "noise"
    % Legacy alias used by older stimulus classes.
    type = "filter";
end

if type == "filter"
    % Filter/noise playback is anchored to the tone LUT.
    lutType = "tone";
    if ~isfinite(value) || value <= 0
        value = obj.ReferenceFrequency;
    end
else
    lutType = type;
end

% ToneLutSource may redirect tone lookups to the swept sine LUT; resolve_tone_lut_
% is the single definition of that choice, shared with test_tones so the table
% the test verifies is the table a stimulus is actually scaled by.
if lutType == "tone"
    lutType = obj.resolve_tone_lut_();
end

if ~isfield(obj.CalibrationData, lutType) || isempty(obj.CalibrationData.(lutType))
    error('stimgen:calibration:Engine:missingTypeCalibration', ...
        'Calibration data for type "%s" is not available.', lutType);
end

d = obj.CalibrationData.(lutType);
if lutType == "swept_sine" || lutType == "tone"
    x = d.frequency;
else
    x = d.duration;
end
z = d.voltage;

% Outside the measured span makima extrapolates a cubic, which can run far
% from anything the speaker does. Said once per table, not per lookup: a bank
% regenerates every variant through here. The latch re-arms whenever
% CalibrationData changes (see Engine's set.CalibrationData).
outside = value(:) < min(x) | value(:) > max(x);
if any(outside) && ~obj.extrapolation_warned_(lutType)
    if lutType == "click"
        span = sprintf('%.4g-%.4g us', min(x) * 1e6, max(x) * 1e6);
        asked = sprintf('%.4g us', value(find(outside, 1)) * 1e6);
    else
        span = sprintf('%.6g-%.6g Hz', min(x), max(x));
        asked = sprintf('%.6g Hz', value(find(outside, 1)));
    end
    stimgen.util.vprintf(0, 1, ...
        ['Calibration lookup at %s lies outside the "%s" table''s measured %s; ' ...
         'its voltage is extrapolated and may be well off. Calibrate over the ' ...
         'range you play. (Reported once per table.)'], asked, lutType, span);
end

n = makima(x, z, value);  % normative voltage at requested parameter
v = n .* 10 .^ ((level - stimgen.calibration.Engine.lut_normative_db(d, obj.NormativeValue)) ./ 20);

end
