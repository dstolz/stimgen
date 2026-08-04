function A = analyze_sweep_response_(obj, x, y, fs, sweep)
% A = analyze_sweep_response_(obj, x, y, fs, sweep)
% Full analysis of one swept-sine excitation/response pair.
%
% Runs the deconvolution once and derives every measure from it, so the
% frequency response, the impulse response, the room decay and the distortion
% figures all describe the same measurement rather than three separately
% regularized versions of it.
%
% Order matters: the impulse response is located and its noise crossing found
% first, because the gate that follows is what keeps the converter noise floor
% and the harmonic products out of the phase and group-delay curves.
%
% Parameters:
%   x     - (:,1) double excitation waveform in volts
%   y     - (:,1) double recorded response
%   fs    - (1,1) double sample rate in Hz
%   sweep - struct with fields duration, start_freq, stop_freq
%
% Returns:
%   A - struct with fields transfer, free_field, impulse, harmonics; see
%       documentation/stimgen_SweptSineCalibration.md

PRE_ONSET_MS      = 5;    % kept ahead of the arrival so the gate has no step in it
HARMONIC_GUARD_MS = 10;   % keep-out between the linear tail and the harmonic cluster
FADE_FRACTION     = 0.1;  % raised-cosine fade at the end of the gate
FADE_MAX_MS       = 20;
DEFAULT_FF_GATE_MS = 20;  % free-field gate when no reflection is found
FF_REFLECTION_MARGIN = 0.8;  % close the free-field gate short of the reflection

A = empty_analysis_(obj, fs);

x = x(:);
y = y(:);
if isempty(x) || isempty(y) || fs <= 0
    return
end

band = [sweep.start_freq, sweep.stop_freq];
[~, ~, h, nfft] = obj.deconvolve_sweep_(x, y, fs);

% Band-limit before any time-domain measure. Outside the swept band the
% regularized deconvolution leaves a broadband floor smeared over the whole
% buffer -- roughly 30 dB above the in-band noise on a quiet system. Left in,
% it flattens the tail of the decay curve and turns every reverberation time
% into a number set by the regularizer rather than by the room.
hb = bandlimit_(obj, h, fs, band);

% The distortion products wrap to the tail of the buffer with the highest
% order nearest the linear response and H2 last, so the linear window stops
% short of the whole cluster -- see harmonic_geometry_. Cutting at H2 instead
% would leave H3 and up inside, where their burst energy lands in the block
% range locate_impulse_ seeds its noise floor from and pins the Schroeder
% decay curve flat for the length of the sweep.
geom = obj.harmonic_geometry_(sweep);
harmonicGuard = round(HARMONIC_GUARD_MS * 1e-3 * fs);
if geom.valid
    searchLast = nfft - round(geom.linear_limit_s * fs) - harmonicGuard;
else
    searchLast = nfft - harmonicGuard;
end
searchLast = max(searchLast, round(0.1 * nfft));

loc = obj.locate_impulse_(hb, fs, searchLast);
if ~isfinite(loc.onset_index)
    return
end

% The transfer function is gated from the unfiltered response: its curves are
% only ever read on a grid inside the swept band, so the band filter would add
% its own edge roll-off for nothing.
preSamples = min(round(PRE_ONSET_MS * 1e-3 * fs), loc.onset_index - 1);
gateFirst = loc.onset_index - preSamples;
hg = window_gate_(h(gateFirst:loc.window_last), preSamples, FADE_FRACTION, ...
                  round(FADE_MAX_MS * 1e-3 * fs));

A.transfer  = obj.estimate_transfer_metrics_(hg, fs, band, gateFirst - 1);
A.impulse   = obj.estimate_impulse_metrics_(hb, fs, loc, band, searchLast);
A.harmonics = obj.estimate_sweep_harmonics_(hb, fs, loc, sweep, geom);

% --- Quasi-anechoic response ---
% Gated ahead of the first reflection, this is the transducer on its own,
% separated from whatever the enclosure adds. The two magnitude curves
% diverging is the signature of a measurement dominated by its surroundings.
ffGateMs = DEFAULT_FF_GATE_MS;
if isfinite(A.impulse.reflections.first_delay_ms)
    ffGateMs = max(A.impulse.reflections.first_delay_ms * FF_REFLECTION_MARGIN, 1);
end
ffLast = min(loc.onset_index + round(ffGateMs * 1e-3 * fs), loc.window_last);
if ffLast - gateFirst > 16
    hff = window_gate_(h(gateFirst:ffLast), preSamples, FADE_FRACTION, ...
                       round(FADE_MAX_MS * 1e-3 * fs));
    A.free_field = obj.estimate_transfer_metrics_(hff, fs, band, gateFirst - 1);
    A.free_field.gate_length_s = (ffLast - loc.onset_index) / fs;
    % One period has to fit inside the gate for the point to mean anything.
    A.free_field.valid_above_hz = 1 / max(A.free_field.gate_length_s, eps);
end

A.valid = true;
end


function A = empty_analysis_(obj, fs)
% Fully formed result with every measure NaN, so a caller can read through the
% sub-structs without first testing whether the analysis ran.
loc0 = obj.locate_impulse_(zeros(0,1), fs, 1);
sweep0 = struct('duration', 1, 'start_freq', 1, 'stop_freq', 2);
empt = obj.estimate_transfer_metrics_(zeros(0,1), fs, [1 2], 0);
ff = empt;
ff.gate_length_s = nan;
ff.valid_above_hz = nan;
A = struct( ...
    'transfer',   empt, ...
    'free_field', ff, ...
    'impulse',    obj.estimate_impulse_metrics_(zeros(0,1), fs, loc0, [1 2], 1), ...
    'harmonics',  obj.estimate_sweep_harmonics_(zeros(0,1), fs, loc0, sweep0), ...
    'valid',      false);
end


function hb = bandlimit_(obj, h, fs, band)
% Restrict an impulse response to the swept band. Falls back to the unfiltered
% response when the band is too close to DC or Nyquist for a stable design.
MIN_NORM_FREQ = 5e-4;

lo = max(band(1), MIN_NORM_FREQ * fs / 2);
hi = min(band(2), 0.49 * fs);
if ~(hi > lo * 1.1)
    hb = h;
    return
end
try
    bp = designfilt('bandpassiir', FilterOrder = 8, ...
        HalfPowerFrequency1 = lo, HalfPowerFrequency2 = hi, SampleRate = fs);
    hb = obj.zero_phase_bandpass_(h, bp);
catch ME
    stimgen.util.vprintf(1, 'Sweep band-limit filter failed (%s); analyzing unfiltered.', ME.message);
    hb = h;
end
end


function g = window_gate_(g, fadeIn, fadeFrac, fadeMax)
% Raised-cosine fades at both ends of a gate. Without them the truncation is a
% step, and a step in the time domain is broadband ripple in the frequency
% domain, which is indistinguishable from real response ripple.
n = numel(g);
g = g(:);

if fadeIn >= 2 && fadeIn < n
    w = 0.5 * (1 - cos(pi * (0:fadeIn-1)' / fadeIn));
    g(1:fadeIn) = g(1:fadeIn) .* w;
end

fadeOut = min(max(round(fadeFrac * n), 2), fadeMax);
fadeOut = min(fadeOut, n - fadeIn - 1);
if fadeOut >= 2
    w = 0.5 * (1 + cos(pi * (0:fadeOut-1)' / fadeOut));
    g(end-fadeOut+1:end) = g(end-fadeOut+1:end) .* w;
end
end
