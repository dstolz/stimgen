function m = estimate_sweep_harmonics_(obj, h, fs, loc, sweep, geom)
% m = estimate_sweep_harmonics_(obj, h, fs, loc, sweep)
% m = estimate_sweep_harmonics_(obj, h, fs, loc, sweep, geom)
% Harmonic distortion recovered from the circular impulse response of a log
% sweep by time-gating.
%
% This is the property that makes a log sweep worth using over noise or MLS.
% Because the sweep spends equal time in every octave, the N-th harmonic
% response of the system arrives at a fixed interval
%
%   dt_N = T * ln(N) / ln(f2/f1)
%
% *ahead of* the linear impulse response, independent of frequency. Circular
% deconvolution wraps those arrivals to the tail of the buffer, where each can
% be gated out and measured on its own. Gating them out is also what makes the
% linear response distortion-free, which is why the frequency and phase curves
% are computed from the gated response.
%
% Levels come from the spectral ratio |H_N(N*f)| / |H_1(f)|, not from the ratio
% of gate energies. A harmonic impulse response is not a scaled copy of the
% linear one -- it carries a different spectral weighting -- so its total energy
% overstates distortion by several dB, whereas the spectral ratio recovers a
% known nonlinearity to within about 1 dB.
%
% MATLAB's thd() cannot be used here: it assumes a stationary sinusoid and
% returns a meaningless number for a chirp.
%
% Parameters:
%   h        - (:,1) double band-limited circular impulse response
%   fs       - (1,1) double sample rate in Hz
%   loc      - struct from locate_impulse_
%   sweep    - struct with fields duration, start_freq, stop_freq
%   geom     - struct from harmonic_geometry_, giving the gate positions;
%              computed from sweep when omitted. The caller passes the same
%              struct it used to place the linear window, so the gates and
%              that window are guaranteed to describe the same cluster.
%
% Returns:
%   m - struct with fields
%       order, delay_ms                    gate position per order
%       level_db, noise_limited            band-median level re fundamental
%       frequency_hz, curve_db             distortion vs excitation frequency
%       h2_curve_db, h3_curve_db, thd_curve_db
%       thd_db, thd_percent, h2_db, h3_db  broadband summary
%       noise_floor_db                     measurement floor re fundamental

CURVE_FRAC_OCT  = 12;
CURVE_PER_OCT   = 12;
NOISE_MARGIN_DB = 6;      % an order this close to the floor reports nothing
MIN_FFT_SECONDS = 0.4;

if nargin < 6 || isempty(geom), geom = obj.harmonic_geometry_(sweep); end

m = struct('order', [], 'delay_ms', [], 'level_db', [], 'noise_limited', [], ...
           'frequency_hz', [], 'curve_db', [], ...
           'h2_curve_db', [], 'h3_curve_db', [], 'thd_curve_db', [], ...
           'thd_db', nan, 'thd_percent', nan, 'h2_db', nan, 'h3_db', nan, ...
           'noise_floor_db', nan);

h = h(:);
nfft = numel(h);
f1 = sweep.start_freq;
f2 = sweep.stop_freq;
if nfft < 16 || fs <= 0 || ~isfinite(loc.peak_index) || ~geom.valid
    return
end

% Gate boundaries: each harmonic owns the interval midway to its neighbours.
% dt grows with order but the spacing shrinks, so high orders crowd together
% and the useful maximum order is set by that crowding, not by the hardware.
orders      = geom.order;
dtN         = geom.dt_s;
edgesBefore = geom.edge_before_s;   % further back in time
edgesAfter  = geom.edge_after_s;    % towards the linear IR

nOrd = numel(orders);
m.order = orders;
m.delay_ms = dtN * 1e3;
m.level_db = nan(nOrd, 1);
m.noise_limited = false(nOrd, 1);

gates = cell(nOrd, 1);
for i = 1:nOrd
    lo = loc.peak_index - round(edgesBefore(i) * fs);
    hi = loc.peak_index - round(edgesAfter(i) * fs);
    if hi - lo < 8
        continue
    end
    gates{i} = h(mod((lo:hi)' - 1, nfft) + 1);   % harmonics live past the wrap point
end
if isempty(gates{1})
    return
end

% The fundamental is gated to the longest harmonic gate, so that truncation of
% the reverberant tail biases numerator and denominator by the same amount.
gateLen = max(cellfun(@numel, gates));
linSeg = h(loc.peak_index : min(loc.peak_index + gateLen - 1, nfft));

nfftC = 2 ^ nextpow2(max(gateLen, round(MIN_FFT_SECONDS * fs)));
faxC = (0:floor(nfftC/2))' .* (fs / nfftC);
magFundFull = abs_half_(fft(linSeg, nfftC));

% Grid runs to f2/2 so the second harmonic is defined across all of it; higher
% orders leave their product outside the swept band sooner and stop earlier.
gridHi = min(f2 / 2, 0.5 * fs);
if ~(gridHi > f1)
    return
end
grid = 2 .^ (log2(f1) : 1/CURVE_PER_OCT : log2(gridHi))';
m.frequency_hz = grid;
m.curve_db = nan(numel(grid), nOrd);

magFund = obj.smooth_to_log_grid_(faxC, magFundFull, grid, CURVE_FRAC_OCT, "power");

% Expected magnitude of pure noise over a gate of this length, for the same
% transform: anything at or below it is a measurement floor, not distortion.
noiseMag = nan;
if isfinite(loc.noise_power) && loc.noise_power > 0
    noiseMag = sqrt(gateLen * loc.noise_power);
    m.noise_floor_db = 20 * log10(noiseMag / max(median(magFund, 'omitnan'), eps));
end

for i = 1:nOrd
    g = gates{i};
    if isempty(g)
        continue
    end
    N = orders(i);
    magN = obj.smooth_to_log_grid_(faxC, abs_half_(fft(g, nfftC)), grid * N, CURVE_FRAC_OCT, "power");
    ratio = 20 * log10((magN + eps) ./ (magFund + eps));
    ratio(grid * N > f2) = nan;      % product falls outside the swept band
    m.curve_db(:, i) = ratio;
    m.level_db(i) = median(ratio, 'omitnan');

    if isfinite(noiseMag)
        m.noise_limited(i) = median(magN, 'omitnan') < noiseMag * 10 ^ (NOISE_MARGIN_DB / 20);
    end
end

valid = isfinite(m.level_db) & ~m.noise_limited;
if any(valid)
    m.thd_db = 10 * log10(sum(10 .^ (m.level_db(valid) / 10)));
    m.thd_percent = 100 * 10 ^ (m.thd_db / 20);
end
if valid(1), m.h2_db = m.level_db(1); end
if nOrd >= 2 && valid(2), m.h3_db = m.level_db(2); end

m.h2_curve_db = m.curve_db(:, 1);
if nOrd >= 2
    m.h3_curve_db = m.curve_db(:, 2);
end

% Each order contributes only where its product is still inside the swept
% band, so the summed curve necessarily thins out towards the top of the grid.
keep = ~m.noise_limited';
total = sum(10 .^ (m.curve_db(:, keep) / 10), 2, 'omitnan');
total(all(isnan(m.curve_db(:, keep)), 2)) = nan;
m.thd_curve_db = 10 * log10(total);
end


function a = abs_half_(X)
% One-sided magnitude of a full-length transform.
a = abs(X(1:floor(numel(X)/2) + 1));
end
