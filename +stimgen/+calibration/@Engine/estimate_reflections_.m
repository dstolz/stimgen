function r = estimate_reflections_(obj, h, fs, loc, maxCount)
% r = estimate_reflections_(obj, h, fs, loc)
% r = estimate_reflections_(obj, h, fs, loc, maxCount)
% Find discrete arrivals after the direct sound in an impulse response.
%
% Peaks are picked from a short-window energy envelope rather than from |h|:
% a band-limited arrival oscillates through zero every half cycle, so peak
% picking on the raw response reports one "reflection" per half period of the
% carrier instead of one per arrival.
%
% Reported times are relative to the direct-sound peak, which makes them
% independent of the converter loopback latency folded into the absolute
% arrival time. Path difference is computed at the speed of sound for the
% engine's AmbientTemperature -- the times are the measurement, the
% distances only the room temperature's reading of them.
%
% Parameters:
%   h        - (:,1) double impulse response, index 1 at the deconvolution origin
%   fs       - (1,1) double sample rate in Hz
%   loc      - struct from locate_impulse_
%   maxCount - (1,1) double most reflections to report (default 12)
%
% Returns:
%   r - struct with fields
%       delay_ms, level_db, polarity, path_difference_m  (count x 1 each)
%       count                   number of arrivals found
%       first_delay_ms          initial time delay gap, direct to first reflection
%       first_level_db          level of that first reflection re direct
%       strongest_delay_ms      arrival of the loudest reflection
%       strongest_level_db      its level re direct
%       detection_floor_db      threshold the search actually used

SPEED_OF_SOUND = obj.SpeedOfSound;   % m/s, dry air at AmbientTemperature
ENVELOPE_MS    = 0.2;      % arrival resolution
MIN_SEPARATION_MS = 0.3;   % two arrivals closer than this are one arrival
FLOOR_DB       = -30;      % quietest reflection worth reporting, re direct;
                           % below this the band-limited direct sound's own
                           % sidelobes start being picked up as arrivals
PROMINENCE_DB  = 6;        % a peak must stand this far out of its surroundings
NOISE_MARGIN_DB = 6;       % ... and clear the noise floor by this much

if nargin < 5, maxCount = 12; end

r = struct('delay_ms', [], 'level_db', [], 'polarity', [], ...
           'path_difference_m', [], 'count', 0, ...
           'first_delay_ms', nan, 'first_level_db', nan, ...
           'strongest_delay_ms', nan, 'strongest_level_db', nan, ...
           'detection_floor_db', nan);

h = h(:);
if isempty(h) || fs <= 0 || ~isfinite(loc.peak_index) || ~isfinite(loc.window_last)
    return
end

envWin = max(round(ENVELOPE_MS * 1e-3 * fs), 3);
env = sqrt(movmean(h .^ 2, envWin));
directEnv = env(loc.peak_index);
if ~(directEnv > 0)
    return
end

minSep = max(round(MIN_SEPARATION_MS * 1e-3 * fs), 2);
first = min(loc.peak_index + minSep, numel(env));
last  = min(loc.window_last, numel(env));
if last - first < minSep
    return
end

floorDb = FLOOR_DB;
if isfinite(loc.noise_power) && loc.noise_power > 0
    noiseDb = 10 * log10(loc.noise_power) - 20 * log10(directEnv);
    floorDb = max(floorDb, noiseDb + NOISE_MARGIN_DB);
end
r.detection_floor_db = floorDb;

seg = env(first:last);
[~, pkIdx] = findpeaks(seg, ...
    MinPeakHeight = directEnv * 10 ^ (floorDb / 20), ...
    MinPeakProminence = directEnv * 10 ^ ((floorDb - PROMINENCE_DB) / 20), ...
    MinPeakDistance = minSep, ...
    NPeaks = maxCount);
if isempty(pkIdx)
    return
end

idx = pkIdx(:) + first - 1;
n = numel(idx);
delaySamp = idx - loc.peak_index;

r.delay_ms = delaySamp / fs * 1e3;
r.level_db = 20 * log10(env(idx) / directEnv);
r.path_difference_m = delaySamp / fs * SPEED_OF_SOUND;
r.count = n;

% Polarity from the largest raw excursion inside the envelope window: an
% inverted reflection off a pressure-release boundary flips the sign, which
% is what distinguishes a reflection from a driver resonance.
r.polarity = zeros(n, 1);
half = max(floor(envWin / 2), 1);
for i = 1:n
    lo = max(idx(i) - half, 1);
    hi = min(idx(i) + half, numel(h));
    [~, k] = max(abs(h(lo:hi)));
    r.polarity(i) = sign(h(lo + k - 1));
end

r.first_delay_ms = r.delay_ms(1);
r.first_level_db = r.level_db(1);
[r.strongest_level_db, k] = max(r.level_db);
r.strongest_delay_ms = r.delay_ms(k);
end
