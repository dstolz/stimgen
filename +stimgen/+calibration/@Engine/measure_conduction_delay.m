function [info, diagnostics] = measure_conduction_delay(obj, options)
% info = measure_conduction_delay(obj)
% info = measure_conduction_delay(obj, Name=Value)
% [info, diagnostics] = measure_conduction_delay(obj, ...)
%
% Standalone probe of the rig's acquisition latency -- acoustic propagation
% from the speaker to the microphone plus the converters' round-trip
% latency, as one bulk delay -- by playing a click and measuring its
% response latency against the excitation. A click is the right probe
% because its autocorrelation is a single sharp peak.
%
% Tone runs do NOT call this: calibrate_tones and test_tones embed a probe
% click at the head of every acquisition instead (see add_click_probe_),
% because latency is only guaranteed within a record -- it need not carry
% across records of different lengths, so a delay measured here on a short
% record cannot be assumed to hold for a two-second train. This method
% remains for probing a rig by hand; both paths share click_latency_, so
% they cannot disagree about what a latency is.
%
% The result is judged before it is trusted -- the click response must
% stand clearly above the record's noise and the measured lag must explain
% where that response actually sits. A failed measurement is stored with
% valid=false and warned about.
%
% Parameters:
%   MaxDelay      - (1,1) double largest delay considered, in seconds
%                   (default 0.05)
%   ClickDuration - (1,1) double click length in seconds (default 100e-6);
%                   clamped up to one sample at the current rate.
%   NumClicks     - (1,1) double clicks in the probe train (default 1).
%                   More clicks buy signal in a noisy room, but a delay
%                   near the click spacing aliases; leave at 1 unless the
%                   single-click response is too weak to detect.
%
% Returns:
%   info - struct, also stored in obj.ConductionDelay:
%     delay_s       - measured delay in seconds (check valid)
%     delay_samples - the same delay in samples at fs
%     fs            - sample rate the measurement was taken at
%     peak_v        - peak of the demeaned click response
%     noise_v       - robust noise level of the record
%     corr          - normalized correlation at the chosen lag; diagnostic
%     at_bound      - correlation peak sat on the MaxDelay search bound
%     valid         - the measurement is trustworthy
%     measuredOn    - datetime of the measurement
%     temperature_c, speed_of_sound_ms, path_m - the air path the delay
%                     implies, and the conditions it was derived at (see
%                     AmbientTemperature)
%
%   diagnostics - the correlation curve the lag was chosen from and the
%     probe-region record it was measured against, on one lag axis (see
%     click_latency_). Also broadcast as the LiveUpdate payload's Latency,
%     so the same panel draws it live or after the fact.
%
% See also: stimgen.calibration.Engine/calibrate_tones,
%           stimgen.calibration.Engine/test_tones,
%           stimgen.calibration.Engine/click_latency_
arguments
    obj
    options.MaxDelay      (1,1) double {mustBePositive, mustBeFinite} = 0.05
    options.ClickDuration (1,1) double {mustBePositive, mustBeFinite} = 100e-6
    options.NumClicks     (1,1) double {mustBeInteger, mustBePositive} = 1
end
obj.assert_adapter_();
% A run of its own, short as it is: a Stop left over from a cancelled sweep
% must not abort this one before it plays, and the live payload's elapsed
% time is measured from here.
obj.reset_cancel_();
obj.begin_run_();
fs = obj.Fs;

clickN  = max(round(options.ClickDuration * fs), 1);
onsetN  = round(0.02 * fs);
maxLagN = max(round(options.MaxDelay * fs), 1);
% Delay, click, and ringdown all fit between clicks, so no click's response
% bleeds into the next one's correlation window.
spacingN = maxLagN + clickN + round(0.03 * fs);

onsets = onsetN + (0:options.NumClicks - 1) .* spacingN + 1;
x = zeros(1, onsets(end) + clickN - 1 + spacingN);
for o = onsets
    x(o : o + clickN - 1) = 1;
end
x = obj.ExcitationVoltage .* x;
obj.ExcitationSignal = x;

obj.throw_if_cancelled_();
y = obj.Adapter.play_and_record(x);
y = obj.ac_couple_response_(obj.trim_response_(y(:).'));
obj.ResponseSignal = y;

% The whole record is probe: x is nonzero only at the clicks already.
[info, diagnostics] = obj.click_latency_(x, y, maxLagN, numel(y));
obj.ConductionDelay = info;

if info.valid
    stimgen.util.vprintf(1, ...
        ['Conduction delay: %.2f ms (%d samples at %.10g Hz; ~%.2f m of air ' ...
         'at %.1f m/s for %.1f C, converter latency included)'], ...
        info.delay_s * 1e3, info.delay_samples, fs, info.path_m, ...
        info.speed_of_sound_ms, info.temperature_c);
elseif info.peak_v <= 10 * max(info.noise_v, eps)
    stimgen.util.vprintf(0, 1, ...
        ['Conduction delay could not be measured: the click response (peak ' ...
         '%.4f V) does not stand above the noise (%.4f V). Check the ' ...
         'microphone and speaker.'], info.peak_v, info.noise_v);
else
    stimgen.util.vprintf(0, 1, ...
        ['Conduction delay could not be measured: a click response is present ' ...
         'but no delay within the %.1f ms search bound aligns it with the ' ...
         'excitation. The true delay is probably larger; raise MaxDelay.'], ...
        options.MaxDelay * 1e3);
end

% The span marks where the click response was found, so the waveform panel
% shows what the delay was read from; Latency carries the correlation the
% delay was actually chosen from, which is the part of the measurement the
% waveform cannot show.
obj.emit_live_("latency", "measure", ...
    'Span', [onsets(1) + info.delay_samples, ...
             min(onsets(end) + clickN - 1 + info.delay_samples, numel(y))], ...
    'Latency', diagnostics);
end
