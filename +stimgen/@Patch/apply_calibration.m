function apply_calibration(obj)
% apply_calibration(obj)
% Apply calibration according to CalibrationMode.
%
% The base implementation picks the LUT lookup key by switching on
% CalibrationType and reading a hardcoded property name (Frequency,
% ClickDuration, StartFrequency/StopFrequency). A patch has no fixed property
% layout, so it overrides the whole method the way stimgen.SoundFile does.
%
% Modes:
%   "Filtered" - equalize with the measured FIR, then scale to the level.
%                Right for broadband or composite patches.
%   "Tone"     - scalar LUT lookup at AnchorFrequency. When AnchorFrequency is
%                0 the anchor is taken from the output chain's dominant
%                oscillator, falling back to the spectral centroid.
%   "None"     - leave the normalized waveform alone.

if ~obj.ApplyCalibration || obj.temporarilyDisableSignalMods
    return
end
if obj.CalibrationMode == "None"
    return
end

C = obj.Calibration;
if ~isa(C, 'stimgen.StimCalibration') || isempty(C.CalibrationData)
    if obj.calibrationWarningIssued
        stimgen.util.vprintf(2, 1, 'No calibration data available for stim');
    else
        stimgen.util.vprintf(0, 1, 'No calibration data available for stim');
        obj.calibrationWarningIssued = true;
    end
    return
end

fs    = double(obj.selected_value("Fs"));
level = double(obj.get_selected_property_value_("SoundLevel"));
y     = obj.Signal;

switch obj.CalibrationMode
    case "Filtered"
        lutType = "filter";
        value   = NaN;

        if isfield(C.CalibrationData, 'filter')
            Hd = C.CalibrationData.filter;
            gd = round(C.CalibrationData.filterGrpDelay);
            if gd > 0
                % Pre/post pad so the FIR start-up transient lands outside the
                % returned span, matching StimType.apply_calibration.
                ypad = filter(Hd, [zeros(1,gd) y zeros(1,gd)]);
                y    = ypad(gd+1 : gd+numel(obj.Signal));
            else
                y = filter(Hd, y);
            end
        else
            error('stimgen:Patch:NoEqualizer', ...
                ['Calibration mode "Filtered" needs an equalization filter, but the ' ...
                 'loaded calibration has none. Use "Tone" or "None", or load a ' ...
                 'calibration that includes a filter.']);
        end

    case "Tone"
        lutType = "tone";
        value   = obj.anchor_frequency_(y, fs);

    otherwise
        error('stimgen:Patch:UnknownCalibrationMode', ...
            'Unknown calibration mode "%s".', obj.CalibrationMode);
end

% Filtering changes the amplitude, so renormalize before scaling to volts.
% This is why gating must come after calibration everywhere in this package.
y = local_normalize(y, obj.LevelReference);

v = C.compute_adjusted_voltage(lutType, value, level);

if v > 10
    warning('stimgen:Patch:apply_calibration:OutOfRange', ...
        ['Calculated voltage %.2f V exceeds 10 V for %.1f dB SPL. ' ...
         'Reduce Sound Level or check the calibration.'], v, level);
end

obj.Signal = v .* y;
end


function y = local_normalize(y, reference)
switch reference
    case "rms"
        d = sqrt(mean(y.^2));
    case "peak"
        d = max(y);
    otherwise
        d = max(abs(y));
end
if isfinite(d) && d > 0
    y = y ./ d;
end
end
