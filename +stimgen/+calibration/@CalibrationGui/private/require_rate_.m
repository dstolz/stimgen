function require_rate_(sampleRate, fsHardware)
% A filter needs a rate: typed, or the attached hardware's.
if sampleRate == 0 && ~(fsHardware > 0)
    error('stimgen:calibration:CalibrationGui:noSampleRate', ...
        ['With no adapter attached there is no hardware rate to fall back on. ' ...
         'Enter the sample rate the filter will run at.']);
end
end
