function info = measure_conduction_delay(obj, options)
% info = measure_conduction_delay(obj)
% info = measure_conduction_delay(obj, Name=Value)
%
% Measure the rig's acquisition latency -- acoustic propagation from the
% speaker to the microphone plus the converters' round-trip latency, as one
% bulk delay -- by playing a short train of clicks and cross-correlating the
% response against the excitation. A click is the right probe because its
% autocorrelation is a single sharp peak; a tone train gives the correlation
% a quasi-periodic ridge to wander along, which is exactly how a per-train
% estimate lands the analysis window early by the unaccounted delay.
%
% calibrate_tones and test_tones call this once at the start of each run --
% the delay is a property of the rig, not of the stimulus, so it is not
% re-estimated before every tone -- and cut every burst window with the
% result. The measurement lands in the observable ConductionDelay property,
% so an attached GUI reports it the moment it exists.
%
% The clicks are spaced further apart than the largest delay considered, so
% the bounded cross-correlation cannot lock onto the wrong click; using
% several of them buys signal over a single click without ambiguity.
%
% The result is judged before it is trusted: the click response must stand
% clearly above the record's robust noise level, and the correlation peak
% must not sit on the search bound. A failed measurement is stored with
% valid=false and warned about; callers fall back to their own alignment.
%
% Parameters:
%   MaxDelay      - (1,1) double largest delay considered, in seconds
%                   (default 0.05). Tone runs pass their GapDuration, which
%                   is the largest delay their segmentation can absorb.
%   ClickDuration - (1,1) double click length in seconds (default 100e-6);
%                   clamped up to one sample at the current rate.
%   NumClicks     - (1,1) double clicks in the probe train (default 3)
%
% Returns:
%   info - struct, also stored in obj.ConductionDelay:
%     delay_s       - measured delay in seconds (NaN-free; check valid)
%     delay_samples - the same delay in samples at fs
%     fs            - sample rate the measurement was taken at
%     peak_v        - peak of the demeaned click response
%     noise_v       - robust noise level of the record
%     corr          - normalized correlation at the chosen lag, 0..1; low
%                     with a strong response means nothing in the search
%                     bound aligns, i.e. the true delay exceeds MaxDelay
%     at_bound      - correlation peak sat on the MaxDelay search bound
%     valid         - the measurement is trustworthy
%     measuredOn    - datetime of the measurement
%
% See also: stimgen.calibration.Engine/calibrate_tones,
%           stimgen.calibration.Engine/test_tones,
%           stimgen.calibration.Engine/align_response_
arguments
    obj
    options.MaxDelay      (1,1) double {mustBePositive, mustBeFinite} = 0.05
    options.ClickDuration (1,1) double {mustBePositive, mustBeFinite} = 100e-6
    options.NumClicks     (1,1) double {mustBeInteger, mustBePositive} = 3
end
obj.assert_adapter_();
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
y = obj.demean_response_(obj.trim_response_(y(:).'));
obj.ResponseSignal = y;

% The correlation always runs demeaned, whatever DemeanResponse says: a DC
% offset biases xcorr toward zero lag, which is the very error this
% measurement exists to remove.
y0 = y - mean(y);

[lagN, atBound] = obj.align_response_(x, y0, maxLagN);

% A click response towers over a mostly-silent record; a peak that does not
% is a disconnected microphone or a muted speaker, and its correlation lag
% is noise.
peakV  = max([abs(y0), 0]);
noiseV = 1.4826 * median(abs(y0));
peakOk = isfinite(peakV) && peakV > 10 * max(noiseV, eps);

% How well the chosen lag actually aligns the two records, as a normalized
% correlation coefficient. A strong response is not enough on its own: a
% delay larger than MaxDelay leaves the bounded search nothing but noise to
% pick from, and the peak it picks is not necessarily on the bound -- the
% lag is garbage while peakOk still holds. Only genuine alignment makes
% this coefficient large.
n = max(min(numel(x), numel(y0) - lagN), 0);
if n > 0
    xa   = x(1:n);
    ya   = y0(lagN + (1:n));
    corr = abs(sum(xa .* ya)) / (norm(xa) * norm(ya) + eps);
else
    corr = 0;
end

valid = peakOk && corr >= 0.1 && ~atBound;

info = struct( ...
    'delay_s',       lagN / fs, ...
    'delay_samples', lagN, ...
    'fs',            fs, ...
    'peak_v',        peakV, ...
    'noise_v',       noiseV, ...
    'corr',          corr, ...
    'at_bound',      atBound, ...
    'valid',         valid, ...
    'measuredOn',    datetime('now'));
obj.ConductionDelay = info;

if valid
    stimgen.util.vprintf(1, ...
        ['Conduction delay: %.2f ms (%d samples at %.10g Hz; ~%.2f m of air ' ...
         'at 343 m/s, converter latency included)'], ...
        info.delay_s * 1e3, lagN, fs, info.delay_s * 343);
elseif ~peakOk
    stimgen.util.vprintf(0, 1, ...
        ['Conduction delay could not be measured: the click response (peak ' ...
         '%.4f V) does not stand above the noise (%.4f V). Check the ' ...
         'microphone and speaker.'], peakV, noiseV);
else
    stimgen.util.vprintf(0, 1, ...
        ['Conduction delay could not be measured: a click response is present ' ...
         'but no delay within the %.1f ms search bound aligns it with the ' ...
         'excitation. The true delay is probably larger; raise the bound ' ...
         '(GapDuration on a tone run).'], options.MaxDelay * 1e3);
end

% The span marks where the click responses were found, so the waveform panel
% shows what the delay was read from.
obj.emit_live_("latency", "measure", ...
    'Span', [onsets(1) + lagN, min(onsets(end) + clickN - 1 + lagN, numel(y))]);
end
