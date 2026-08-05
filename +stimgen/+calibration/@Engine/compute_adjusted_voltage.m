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

% Redirect tone lookups to the swept sine LUT when so configured -- the two
% are on the same SPL/voltage scale. Fall back to the tone LUT rather than
% error when no sweep has been run, so setting the source ahead of the
% measurement is harmless.
if lutType == "tone" && obj.ToneLutSource == "swept_sine"
    if isfield(obj.CalibrationData, 'swept_sine') && ~isempty(obj.CalibrationData.swept_sine)
        lutType = "swept_sine";
    else
        stimgen.util.vprintf(2, ...
            'ToneLutSource is "swept_sine" but no swept sine calibration exists; using the tone LUT.');
    end
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

n = makima(x, z, value);  % normative voltage at requested parameter
v = n .* 10 .^ ((level - obj.NormativeValue) ./ 20);

end
