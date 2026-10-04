function run_design_filter_(obj, source, opts)
args = namedargs2cell(opts);
obj.Engine.design_filter(source, args{:});
D = obj.Engine.CalibrationData.filterDesign;
% %.10g: full precision for TDT-style non-integer rates
% (24414.0625), plain "44100" for integer ones. %g would show two
% nearly equal rates as the same number while calling them
% mismatched.
msg = sprintf( ...
    'Equalization filter designed: %d taps, %.1f dB correction span, Fs = %.10g Hz.', ...
    D.numCoefficients, D.correctionDb, D.sampleRate);

% The number a hardware chain scales its gain against, stated at
% design time so it travels with the taps it belongs to. Guarded:
% the reference needs the LUT lookup, which can still refuse.
try
    rRef = obj.Engine.filter_level_reference(1);
    msg = sprintf(['%s 1 V RMS white noise at unity gain: %.1f dB SPL ' ...
        '(scale by %.3g for %g dB SPL).'], ...
        msg, rRef.unityGainSpl, rRef.scale, rRef.normativeValue);
catch
end

% A filter cut for a rate other than the one attached is a
% legitimate thing to want, and a silent trap if it was not
% intended -- test_filter and apply_calibration (through
% stimgen.util.assert_filter_rate) both refuse it. Flag it on the
% way out, before either is reached.
fsHardware = obj.Engine.Fs;
isOverride = fsHardware > 0 && abs(D.sampleRate - fsHardware) > 1e-6 * fsHardware;
if isOverride
    msg = sprintf(['%s The attached hardware runs at %.10g Hz, so this filter is ' ...
        'for another rig -- it cannot be tested or used here.'], msg, fsHardware);
end
obj.set_status_(msg, isOverride);
end
