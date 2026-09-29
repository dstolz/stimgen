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
% correlation. The correlation's first arrival -- the first causal sample
% rising above the largest peak of the correlation at negative lags, rather
% than its maximum, which ringing or a reflection can pull later than the
% direct arrival (see align_response_) -- only locates the response. The
% delay itself is read off the response waveform there: a line fit to the
% leading edge of its first lobe, extrapolated to where it crosses the
% pre-click noise floor (see rise_onset_ below). A threshold crossing, on
% the correlation or on the waveform, dates the arrival by wherever a
% gradually rising response happens to clear the threshold, which reads
% late by a fraction of the rise; the extrapolated edge does not, and it is
% sub-sample.
% The result is judged before it is trusted, inside the probe region only
% (the record's head, before any tone burst):
%
%   - the response peak there must stand clearly above the region's robust
%     noise level -- otherwise the microphone or speaker is dead and the
%     lag is noise;
%   - the record must actually carry a response where the measured lag
%     predicts one: the peak inside a short window at the predicted arrival
%     has to clear that same floor. A lag pointing at silence means nothing
%     inside the search bound aligns, which is what a delay larger than
%     maxLagN looks like (the bounded search then picks a noise crossing
%     that is rarely on the bound itself). The test is deliberately local --
%     asking instead that the region's *loudest* peak be the arrival would
%     fail every rig whose reflection or ringdown outweighs its direct
%     sound, which is the case the first-arrival lag exists to get right;
%   - the chosen lag must not sit on the bound.
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
%     delay_s, delay_samples - the measured latency (check valid); delay_s is
%                              sub-sample, delay_samples the nearest whole
%                              sample
%     fs                     - sample rate the measurement was taken at
%     peak_v, noise_v        - probe-region response peak and robust noise
%     corr                   - normalized correlation over the click
%                              support at the chosen lag; diagnostic only
%     at_bound               - chosen lag sat on the search bound
%     valid                  - the measurement is trustworthy
%     measuredOn             - datetime of the measurement
%     temperature_c          - AmbientTemperature the path was derived at
%     speed_of_sound_ms      - speed of sound at that temperature
%     path_m                 - air path the delay implies (delay x speed)
%
%   diagnostics - struct of the evidence the verdict was reached from, for
%     a caller that draws or archives it. Built only when asked for, so a
%     sweep taking one of these per acquisition pays nothing for it:
%     lag_ms, corr           - the searched correlation curve, over the full
%                              [-bound, bound] lag span
%     corr_threshold         - the pre-excitation correlation peak the
%                              arrival had to rise above, on corr's
%                              normalized scale
%     probe_v, probe_lag0_ms - the probe-region response and where its first
%                              sample sits relative to the click onset, so
%                              record and correlation share one lag axis
%     onset_fit_ms, onset_fit_v - the fitted leading edge as a segment, from
%                              its floor crossing (the delay) up to the
%                              lobe's peak; NaN when no fit was possible and
%                              the correlation's lag stands
%     onset_floor_v          - the pre-click noise floor the edge was
%                              extrapolated to (3x robust SD)
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
clickIdx = find(xClick(1:min(numel(xClick), n)) ~= 0);

% The correlation only locates the arrival. Its toe precedes the response by
% the click's width, and where it crosses a threshold depends on how fast the
% response rises, so the onset itself is read off the response waveform: the
% leading edge of its first lobe, extrapolated down to the pre-click noise.
onsetN = lagN;
fit = [];
if ~isempty(clickIdx)
    clickN = find(diff(clickIdx) > 1, 1);
    if isempty(clickN)
        clickN = numel(clickIdx);
    end
    [onsetN, fit] = rise_onset_(region, clickIdx(1), clickN, lagN, fs);
end
lagN = round(onsetN);

% A click response towers over its otherwise-silent probe region; a peak
% that does not is a disconnected microphone or a muted speaker.
peakV  = max([abs(region), 0]);
noiseV = 1.4826 * median(abs(region));
floorV = 10 * max(noiseV, eps);
peakOk = isfinite(peakV) && peakV > floorV;

% Is there a response where the lag says one should be? Measured over a
% window opening just before the predicted arrival and closing after the
% ringdown, so a speaker whose energy peaks a moment after onset still
% counts. Anything louder elsewhere in the region -- a reflection, a
% ringdown of a previous click -- is irrelevant to whether this arrival is
% real, and is deliberately not consulted.
tolPre   = round(0.5e-3 * fs);
ringN    = round(3e-3 * fs);
arrivalV = 0;
for ci = clickIdx
    lo = max(ci + lagN - tolPre, 1);
    hi = min(ci + lagN + ringN, numel(region));
    if lo <= hi
        arrivalV = max(arrivalV, max(abs(region(lo:hi))));
    end
end
agree = ~isempty(clickIdx) && arrivalV > floorV;

% Diagnostic only: how strongly the click support correlates at the chosen
% lag. Not gated on -- the agreement test above is the discriminator.
corr = 0;
if ~isempty(clickIdx) && clickIdx(end) + lagN <= numel(y0)
    xa = xClick(clickIdx);
    ya = y0(clickIdx + lagN);
    corr = abs(sum(xa .* ya)) / (norm(xa) * norm(ya) + eps);
end

% Sub-sample, from the fit; delay_samples is the whole-sample lag the
% segmentation cuts records with.
delayS = onsetN / fs;
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
    'corr_threshold',    curve.threshold, ...
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
    'path_m',            info.path_m, ...
    'onset_fit_ms',      [NaN NaN], ...
    'onset_fit_v',       [NaN NaN], ...
    'onset_floor_v',     NaN);

% The line the onset was read from, on the same lag axis as the record.
if ~isempty(fit)
    diagnostics.onset_fit_ms  = fit.lag_samples ./ fs .* 1e3;
    diagnostics.onset_fit_v   = fit.v;
    diagnostics.onset_floor_v = fit.floor_v;
end
end

% ------------------------------------------------------------------------ %
function [onsetN, fit] = rise_onset_(y, c1, clickN, lagN, fs)
% Onset of the click response, in samples after the click onset c1, from the
% leading edge of the response's first lobe.
%
% The noise floor is measured on the samples before the click played (so it
% cannot contain any response): baseline = their median, floor = 3x their
% robust standard deviation. Around the correlation's arrival, the first
% lobe is the first excursion reaching 20% of the local peak; a line is fit
% to its leading edge between 20% and 80% of the lobe's own peak, and the
% onset is where that line crosses the floor. That discards the slow toe a
% threshold crossing would date the arrival by, and gives a sub-sample
% reading. A rise too steep to put two samples in that band -- a sampled
% step -- falls back to the two samples straddling half height.
%
% Returns lagN unchanged, and fit = [], when there is no pre-click record to
% measure the floor on or no lobe to fit.
onsetN = lagN;
fit    = [];

pre = y(1:c1 - 1);
if numel(pre) < 16
    return
end
base   = median(pre);
floorV = 3 * max(1.4826 * median(abs(pre - base)), eps);

% The correlation's lag can land after the true onset by up to the click
% width plus however long the response takes to rise; 1 ms covers both.
lo = max(c1 + lagN - clickN - round(1e-3 * fs), c1);
hi = min(c1 + lagN + round(3e-3 * fs), numel(y));
if hi - lo < 2
    return
end
w = y(lo:hi) - base;

detV = max(0.2 * max(abs(w)), 2 * floorV);
i1 = find(abs(w) > detV, 1);
if isempty(i1)
    return
end
sw = sign(w(i1)) .* w;

% The lobe is the run above detV from i1; its peak is the top of the edge.
iEnd = i1;
while iEnd < numel(sw) && sw(iEnd + 1) > detV
    iEnd = iEnd + 1;
end
[A, p] = max(sw(i1:iEnd));
p = p + i1 - 1;

% The edge starts at the last sample at or below the floor before the lobe.
e0 = i1;
while e0 > 1 && sw(e0 - 1) > floorV
    e0 = e0 - 1;
end
e0 = max(e0 - 1, 1);

edge = e0:p;
sel  = edge(sw(edge) >= 0.2 * A & sw(edge) <= 0.8 * A);
if numel(sel) < 2
    k = find(sw(e0:p) > 0.5 * A, 1) + e0 - 1;
    if isempty(k) || k <= 1
        return
    end
    sel = [k - 1, k];
end

t = sel - sel(1);
c = polyfit(t, sw(sel), 1);
if ~all(isfinite(c)) || c(1) <= 0
    return
end
t0 = (floorV - c(2)) / c(1) + sel(1);
tA = (A - c(2)) / c(1) + sel(1);
t0 = min(max(t0, 1), p);

% Window index -> samples after the click onset.
toLag  = @(k) lo - 1 + k - c1;
onsetN = max(toLag(t0), 0);

s = sign(w(i1));
fit = struct( ...
    'lag_samples', [toLag(t0), toLag(tA)], ...
    'v',           base + s .* [floorV, A], ...
    'floor_v',     floorV);
end
