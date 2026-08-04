function m = estimate_impulse_metrics_(obj, h, fs, loc, band, searchLast)
% m = estimate_impulse_metrics_(obj, h, fs, loc, band, searchLast)
% Room-acoustic and timing measures derived from the deconvolved impulse
% response of a swept-sine calibration run.
%
% Everything here describes the acoustic path between the transducer and the
% microphone, which the frequency response alone cannot show: how long sound
% takes to arrive, what arrives after it, how long the energy takes to decay,
% and how much of what the microphone hears is direct rather than reverberant.
% For a calibration setup those numbers say whether the measurement is being
% made in an effectively free field or whether the enclosure is imposing its
% own response on every stimulus that will later be presented.
%
% Definitions follow ISO 3382-1 (EDT/T20/T30, C50/C80, D50, Ts) with Chu noise
% compensation and Lundeby truncation applied before every integration.
%
% Parameters:
%   h          - (:,1) double circular impulse response from deconvolve_sweep_
%   fs         - (1,1) double sample rate in Hz
%   loc        - struct from locate_impulse_
%   band       - (1,2) double swept band [start stop] in Hz
%   searchLast - (1,1) double last index of the linear response region
%
% Returns:
%   m - struct; see documentation/stimgen_SweptSineCalibration.md for the
%       full field list

DIRECT_WINDOW_MS = 2.5;    % half-width of the direct-sound window for DRR
STORE_MAX_S      = 2;      % hard cap on the stored impulse response
STORE_MIN_S      = 0.25;   % ... and the minimum kept regardless of decay
STORE_MAX_SAMPLES = 2^18;  % decimate rather than bloat the .esgc beyond this
PRE_ONSET_MS     = 5;      % kept ahead of the onset so the rise is visible

m = struct( ...
    'arrival_delay_s', nan, 'peak_delay_s', nan, ...
    'noise_floor_db', nan, 'inr_db', nan, ...
    'truncation_time_s', nan, 'record_truncated', false, ...
    'impulse_response', [], 'impulse_response_time_s', [], ...
    'impulse_response_fs', nan, ...
    'reflections', [], 'decay', [], 'octave_bands', [], ...
    'c50_db', nan, 'c80_db', nan, 'd50', nan, ...
    'center_time_s', nan, 'drr_db', nan, 'direct_polarity', nan);

% Populate the sub-structs unconditionally so callers can read through them
% even when the analysis bails out below.
m.reflections  = obj.estimate_reflections_(zeros(0,1), fs, loc);
m.decay        = obj.decay_times_(zeros(0,1), fs, nan);
m.octave_bands = struct('center_hz', [], 'edt_s', [], 't20_s', [], ...
                        't30_s', [], 'rt60_s', [], 'inr_db', []);

h = h(:);
if isempty(h) || fs <= 0 || ~isfinite(loc.onset_index)
    return
end

onset = loc.onset_index;
last  = loc.window_last;

m.arrival_delay_s   = (onset - 1) / fs;
m.peak_delay_s      = (loc.peak_index - 1) / fs;
% A negative direct peak means the acoustic chain inverts polarity somewhere;
% worth knowing before a click stimulus is used to time anything.
m.direct_polarity   = sign(h(loc.peak_index));
m.inr_db            = loc.inr_db;
m.truncation_time_s = (loc.truncation_index - onset) / fs;
m.record_truncated  = loc.truncated;
if isfinite(loc.noise_power) && loc.noise_power > 0
    m.noise_floor_db = 10 * log10(loc.noise_power / max(h(loc.peak_index) ^ 2, eps));
end

m.reflections = obj.estimate_reflections_(h, fs, loc);
m.decay = obj.decay_times_(h(onset:last), fs, loc.noise_power);

% --- Energy ratios, all integrated from the onset over the truncated decay ---
e = h(onset:last) .^ 2;
if isfinite(loc.noise_power) && loc.noise_power > 0
    e = max(e - loc.noise_power, 0);
end
totalE = sum(e);
if totalE > 0
    n50 = min(round(0.050 * fs), numel(e));
    n80 = min(round(0.080 * fs), numel(e));
    early50 = sum(e(1:n50));
    early80 = sum(e(1:n80));
    m.c50_db = 10 * log10(max(early50, eps) / max(totalE - early50, eps));
    m.c80_db = 10 * log10(max(early80, eps) / max(totalE - early80, eps));
    m.d50 = early50 / totalE;
    m.center_time_s = sum(((0:numel(e)-1)' / fs) .* e) / totalE;

    % Direct-to-reverberant: a short symmetric window on the direct arrival
    % against everything after it. Below roughly 0 dB the microphone is
    % hearing the enclosure more than the transducer.
    halfWin = max(round(DIRECT_WINDOW_MS * 1e-3 * fs), 1);
    dLo = max(loc.peak_index - halfWin - onset + 1, 1);
    dHi = min(loc.peak_index + halfWin - onset + 1, numel(e));
    directE = sum(e(dLo:dHi));
    m.drr_db = 10 * log10(max(directE, eps) / max(totalE - directE, eps));
end

m.octave_bands = octave_band_decay_(obj, h, fs, band, searchLast);

% --- Store a bounded slice of the response ---
keepS = STORE_MIN_S;
if isfinite(m.decay.rt60_s)
    keepS = max(keepS, 1.5 * m.decay.rt60_s);
end
keepS = min(keepS, STORE_MAX_S);
storeFirst = max(onset - round(PRE_ONSET_MS * 1e-3 * fs), 1);
storeLast  = min(min(onset + round(keepS * fs), last), numel(h));
slice = h(storeFirst:storeLast);
t0 = (storeFirst - onset) / fs;

storeFs = fs;
r = ceil(numel(slice) / STORE_MAX_SAMPLES);
if r > 1
    slice = decimate(slice, r);   % anti-aliased, unlike plain subsampling
    storeFs = fs / r;
end
m.impulse_response = slice(:);
m.impulse_response_time_s = t0 + (0:numel(slice)-1)' / storeFs;
m.impulse_response_fs = storeFs;
end


function b = octave_band_decay_(obj, h, fs, band, searchLast)
% Per-octave reverberation times. Broadband RT is dominated by whichever band
% carries the most energy; a calibration enclosure is almost never uniform
% across frequency, so the per-band figures are what predict how a given
% stimulus will actually decay.
MIN_NORM_FREQ = 5e-4;   % below this the order-8 IIR band filter is ill-conditioned

b = struct('center_hz', [], 'edt_s', [], 't20_s', [], 't30_s', [], ...
           'rt60_s', [], 'inr_db', []);

centers = 2 .^ (log2(62.5) + (0:9))';         % 62.5 Hz .. 32 kHz nominal
lo = centers / sqrt(2);
hi = centers * sqrt(2);
usable = lo >= band(1) & hi <= min(band(2), 0.45 * fs) & lo / (fs/2) >= MIN_NORM_FREQ;
centers = centers(usable);
lo = lo(usable);
hi = hi(usable);
if isempty(centers)
    return
end

n = numel(centers);
b.center_hz = centers;
b.edt_s  = nan(n, 1);
b.t20_s  = nan(n, 1);
b.t30_s  = nan(n, 1);
b.rt60_s = nan(n, 1);
b.inr_db = nan(n, 1);

seg = h(1:min(searchLast, numel(h)));
for i = 1:n
    try
        bp = designfilt('bandpassiir', FilterOrder = 8, ...
            HalfPowerFrequency1 = lo(i), HalfPowerFrequency2 = hi(i), ...
            SampleRate = fs);
        hb = obj.zero_phase_bandpass_(seg, bp);
    catch ME
        stimgen.util.vprintf(2, 'Octave band %.0f Hz skipped: %s', centers(i), ME.message);
        continue
    end

    bLoc = obj.locate_impulse_(hb, fs, numel(hb));
    if ~isfinite(bLoc.onset_index)
        continue
    end
    d = obj.decay_times_(hb(bLoc.onset_index:bLoc.window_last), fs, bLoc.noise_power);
    b.edt_s(i)  = d.edt_s;
    b.t20_s(i)  = d.t20_s;
    b.t30_s(i)  = d.t30_s;
    b.rt60_s(i) = d.rt60_s;
    b.inr_db(i) = bLoc.inr_db;
end
end
