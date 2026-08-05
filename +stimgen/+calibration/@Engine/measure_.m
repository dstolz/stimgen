function r = measure_(obj, signal, mode, options)
% r = measure_(obj, signal, mode)
% r = measure_(obj, signal, mode, Record=true)
% Play signal and return the requested measurement metric.
%
% Parameters:
%   signal          - (1,:) double scaled excitation waveform. With
%                     Record=true it is silence, and only its length (the
%                     acquisition duration) matters.
%   mode            - "rms" | "peak" | "specfreq"
%   StimFrequency   - double (required for "specfreq")
%   Record          - logical; acquire without driving the speaker. Used by
%                     calibrate_reference, where the sound source is an
%                     external acoustic calibrator on the microphone.
%
% Returns:
%   r - scalar measurement in volts (RMS, peak, or spectral RMS)
arguments
    obj
    signal  (1,:) double
    mode    (1,1) string {mustBeMember(mode,["rms","peak","specfreq"])}
    options.StimFrequency (1,1) double = 0
    options.Record (1,1) logical = false
end

if options.Record
    raw = obj.Adapter.record(numel(signal));
else
    raw = obj.Adapter.play_and_record(signal);
end
y   = obj.trim_response_(raw);
obj.ResponseSignal = y;
obj.ResponseTHD    = thd(y, obj.Fs);

switch mode
    case "rms"
        r = sqrt(mean(y.^2));
    case "peak"
        r = max(abs(y));
    case "specfreq"
        r = stimgen.calibration.Engine.spectral_rms(y, options.StimFrequency, obj.Fs);
end
end
