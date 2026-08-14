function [info, diagnostics] = click_latency_(obj, xClick, y, maxLagN, regionEnd)
% info = click_latency_(obj, xClick, y, maxLagN, regionEnd)
% [info, diagnostics] = click_latency_(obj, xClick, y, maxLagN, regionEnd)
% Latency of a click's response within the record that contains it.
%
% The one estimator behind every conduction delay measurement: the
% standalone measure_conduction_delay probe and the click embedded at the
% head of each tone-train acquisition both come here, so the delay a tone
% run segments with and the delay a manual probe reports cannot be computed
% two different ways.
%
% The lag comes from a bounded cross-correlation of the response against
% xClick -- the excitation with everything but the probe click(s) zeroed,
% which is what keeps a tonal train sharing the record from smearing the
% correlation. The result is judged before it is trusted, inside the probe
% region only (the record's head, before any tone burst):
%
%   - the response peak there must stand clearly above the region's robust
%     noise level -- otherwise the microphone or speaker is dead and the
%     lag is noise;
%   - that peak must sit where the measured lag predicts a click response,
%     within a short ring window -- a strong response whose peak the lag
%     does not explain means nothing inside the search bound aligns, which
%     is what a delay larger than maxLagN looks like (the bounded search
%     then picks a noise peak that is rarely on the bound itself);
%   - the correlation peak must not sit on the bound.
%
% Parameters:
%   xClick    - (1,:) double excitation with only the probe click(s)
%               nonzero; amplitude scale is irrelevant
%   y         - (1,:) double the recorded response, full record
%   maxLagN   - (1,1) double largest delay considered, in samples
%   regionEnd - (1,1) double last sample of the probe region: the span of
%               the record that contains only the click response and
%               silence. numel(y) when the whole record is the probe.
%
% Returns:
%   info - struct:
%     delay_s, delay_samples - the measured latency (check valid)
%     fs                     - sample rate the measurement was taken at
%     peak_v, noise_v        - probe-region response peak and robust noise
%     corr                   - normalized correlation over the click
%                              support at the chosen lag; diagnostic only
%     at_bound               - correlation peak sat on the search bound
%     valid                  - the measurement is trustworthy
%     measuredOn             - datetime of the measurement
%     temperature_c          - AmbientTemperature the path was derived at
%     speed_of_sound_ms      - speed of sound at that temperature
%     path_m                 - air path the delay implies (delay x speed)
%
%   diagnostics - struct of the evidence the verdict was reached from, for
%     a caller that draws or archives it. Built only when asked for, so a
%     sweep taking one of these per acquisition pays nothing for it:
%     lag_ms, corr           - the searched correlation curve
%     probe_v, probe_lag0_ms - the probe-region response and where its first
%                              sample sits relative to the click onset, so
%                              record and correlation share one lag axis
%     bound_ms               - the search bound, in the same units
%     plus delay_ms, peak_v, noise_v, valid, at_bound, fs and the speed of
%     sound, so the panel drawing it needs nothing but this struct
%
% See also: stimgen.calibration.Engine/measure_conduction_delay,
%           stimgen.calibration.Engine/align_response_

fs = obj.Fs;

% The correlation always runs demeaned, whatever AcCoupleResponse says: a DC
% offset biases xcorr toward zero lag, which is the very error this
% measurement exists to remove.
y0 = y - mean(y);

[lagN, atBound, curve] = obj.align_response_(xClick, y0, maxLagN);

n = max(min(regionEnd, numel(y0)), 0);
region = y0(1:n);

% A click response towers over its otherwise-silent probe region; a peak
% that does not is a disconnected microphone or a muted speaker.
peakV  = max([abs(region), 0]);
noiseV = 1.4826 * median(abs(region));
peakOk = isfinite(peakV) && peakV > 10 * max(noiseV, eps);

% Does the lag explain the region's peak? Direct arrival lands on the
% predicted sample; the ring window absorbs a speaker whose energy peaks a
% moment after onset.
clickIdx = find(xClick(1:min(numel(xClick), n)) ~= 0);
[~, peakIdx] = max([abs(region), 0]);
tolPre = round(0.5e-3 * fs);
ringN  = round(3e-3 * fs);
d      = peakIdx - lagN - clickIdx;
agree  = ~isempty(clickIdx) && any(d >= -tolPre & d <= ringN);

% Diagnostic only: how strongly the click support correlates at the chosen
% lag. Not gated on -- the agreement test above is the discriminator.
corr = 0;
if ~isempty(clickIdx) && clickIdx(end) + lagN <= numel(y0)
    xa = xClick(clickIdx);
    ya = y0(clickIdx + lagN);
    corr = abs(sum(xa .* ya)) / (norm(xa) * norm(ya) + eps);
end

delayS = lagN / fs;
speed  = obj.SpeedOfSound;

info = struct( ...
    'delay_s',       delayS, ...
    'delay_samples', lagN, ...
    'fs',            fs, ...
    'peak_v',        peakV, ...
    'noise_v',       noiseV, ...
    'corr',          corr, ...
    'at_bound',      atBound, ...
    'valid',         peakOk && agree && ~atBound, ...
    'measuredOn',    datetime('now'), ...
    'temperature_c',     obj.AmbientTemperature, ...
    'speed_of_sound_ms', speed, ...
    'path_m',            delayS * speed);

if nargout < 2
    return
end

% Everything the correlation and the record are read against, on one lag
% axis anchored to the click onset: sample 1 of the region sits that far
% before the click, so a response drawn on it lands where its own delay
% says it should.
if isempty(clickIdx)
    lag0Ms = 0;
else
    lag0Ms = -(clickIdx(1) - 1) / fs * 1e3;
end

diagnostics = struct( ...
    'fs',                fs, ...
    'lag_ms',            curve.lag_samples ./ fs .* 1e3, ...
    'corr',              curve.value, ...
    'probe_v',           region, ...
    'probe_lag0_ms',     lag0Ms, ...
    'delay_ms',          delayS * 1e3, ...
    'bound_ms',          maxLagN / fs * 1e3, ...
    'peak_v',            peakV, ...
    'noise_v',           noiseV, ...
    'at_bound',          atBound, ...
    'valid',             info.valid, ...
    'temperature_c',     obj.AmbientTemperature, ...
    'speed_of_sound_ms', speed, ...
    'path_m',            info.path_m);
end
