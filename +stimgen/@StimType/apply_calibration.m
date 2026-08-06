function apply_calibration(obj)
% apply_calibration(obj)
% Apply either scalar (LUT) calibration or filter+gain calibration to obj.Signal.
% Sets Signal to the voltage-scaled waveform. Has no effect when
% ApplyCalibration is false or temporarilyDisableSignalMods is true.

if ~obj.ApplyCalibration || obj.temporarilyDisableSignalMods
    return
end

C = obj.Calibration;

if ~isa(C,'stimgen.StimCalibration') || isempty(C.CalibrationData)
    if obj.calibrationWarningIssued
        stimgen.util.vprintf(2,1,'No calibration data available for stim');
    else
        stimgen.util.vprintf(0,1,'No calibration data available for stim');
        obj.calibrationWarningIssued = true;
    end
    return
end

type  = obj.CalibrationType;
level = double(obj.get_selected_property_value_("SoundLevel"));

% Resolve LUT "value" where relevant
switch type
    case "tone"
        value = double(obj.get_selected_property_value_("Frequency"));
    case "click"
        value = double(obj.get_selected_property_value_("ClickDuration"));
    case "swept_sine"
        % Use geometric mean of start/stop as the representative frequency for LUT lookup.
        f1 = double(obj.get_selected_property_value_("StartFrequency"));
        f2 = double(obj.get_selected_property_value_("StopFrequency"));
        value = sqrt(f1 * f2);
    otherwise
        value = NaN;
end

% Start with the generated signal; may be replaced by filtered version.
y = obj.Signal;

% --- Filter-based calibration: equalize spectrum + apply level gain ---
if type == "filter" && isfield(C.CalibrationData,'filter')

    Hd = C.CalibrationData.filter;

    % The taps realize their designed response only at the rate they were
    % fitted for, and a mismatch is invisible in the output.
    stimgen.util.assert_filter_rate(C.CalibrationData, double(obj.Fs));

    % Equalize in place: same length, same onset sample as the ungated signal.
    y = stimgen.util.filter_aligned(Hd, obj.Signal, ...
        round(C.CalibrationData.filterGrpDelay));
end

switch obj.Normalization
    case "absmax"
        y = y ./ max(abs(y));
    case "max"
        y = y ./ max(y);
    case "min"
        y = y ./ min(y);
    case "rms"
        y = y ./ sqrt(mean(y.^2));
end

% Apply level (scalar) calibration for the filtered waveform
v = C.compute_adjusted_voltage(type,value,level);

if v > 10
    warning('stimgen:StimType:apply_calibration:OutOfRange', ...
        'Calculated voltage value > 10 V')
end

obj.Signal = v .* y;
