function metrics = estimate_transfer_metrics_(obj, hg, fs, band, bulkDelaySamples, perOctave)
% metrics = estimate_transfer_metrics_(obj, hg, fs, band, bulkDelaySamples)
% metrics = estimate_transfer_metrics_(obj, hg, fs, band, bulkDelaySamples, perOctave)
% Frequency-domain measures of a gated impulse response.
%
% Works from the gated impulse response rather than from a raw Y/X ratio. The
% raw ratio carries the converter noise floor at every frequency and, for a log
% sweep, the harmonic distortion products as well; both wreck the phase and
% group delay curves, which differentiate the spectrum and so amplify exactly
% that noise. Gating the response in time discards them before the transform.
%
% Phase is reported relative to the start of the gate, so the bulk propagation
% and converter latency appears as bulk_delay_s rather than as a phase slope
% steep enough to hide everything else. Group and phase delay are reported
% absolute, with that bulk delay added back.
%
% The minimum-phase/excess-phase split separates the phase that any system with
% this magnitude response must have from the part that is genuinely extra:
% pure delay, all-pass behaviour, and non-minimum-phase notches from
% reflections. Excess group delay is therefore the frequency-dependent arrival
% time, which is what matters when a stimulus has to be timed against a
% physiological recording.
%
% Parameters:
%   hg               - (:,1) double gated impulse response, faded at its end
%   fs               - (1,1) double sample rate in Hz
%   band             - (1,2) double swept band [start stop] in Hz
%   bulkDelaySamples - (1,1) double samples between the deconvolution origin
%                      and the first sample of hg
%   perOctave        - (1,1) double log grid density (default 24 points/octave)
%
% Returns:
%   metrics - struct; see documentation/stimgen_SweptSineCalibration.md

SMOOTH_FRAC_OCT = 24;
MIN_FFT_SECONDS = 0.25;   % floor on transform length, for usable low-frequency resolution

if nargin < 6, perOctave = 24; end

metrics = struct( ...
    'frequency_hz', [], 'magnitude_db', [], 'phase_deg', [], ...
    'minimum_phase_deg', [], 'excess_phase_deg', [], ...
    'group_delay_seconds', [], 'group_delay_samples', [], ...
    'excess_group_delay_seconds', [], 'phase_delay_seconds', [], ...
    'bulk_delay_s', nan, 'magnitude_deviation_db', [], ...
    'flatness_std_db', nan, 'magnitude_ripple_db', nan, ...
    'group_delay_variation_s', nan);

hg = hg(:);
if isempty(hg) || fs <= 0 || numel(hg) < 8
    return
end
if nargin < 5 || ~isfinite(bulkDelaySamples)
    bulkDelaySamples = 0;
end

nfft = 2 ^ nextpow2(max(numel(hg), round(MIN_FFT_SECONDS * fs)));
H = fft(hg, nfft);
half = 1:(floor(nfft/2) + 1);
fax = (half - 1)' .* (fs / nfft);

% Group delay from the derivative theorem, tau = Re{FFT(n*h)/FFT(h)}/fs.
% Differentiating the unwrapped phase instead adds a numerical derivative on
% top of a phase estimate that is already noisy where |H| is small.
Hn = fft((0:numel(hg)-1)' .* hg, nfft);
Hpow = abs(H) .^ 2;
gdSamples = real(Hn .* conj(H)) ./ max(Hpow, 1e-12 * mean(Hpow));
gdSamples = gdSamples(half);

phaseRad = unwrap(angle(H(half)));

% Minimum phase by the real-cepstrum fold: causal part of the cepstrum of
% log|H| gives the Hilbert transform relation between magnitude and phase.
logMag = log(abs(H) + eps);
cep = real(ifft(logMag));
fold = zeros(nfft, 1);
fold(1) = 1;
fold(2:nfft/2) = 2;
fold(nfft/2 + 1) = 1;
phaseMinRad = imag(fft(cep .* fold));
phaseMinRad = phaseMinRad(half);

omega = 2 * pi * fax / fs;
dOmega = max(gradient(omega), eps);
gdMinSamples = -gradient(phaseMinRad) ./ dOmega;

bulkDelayS = bulkDelaySamples / fs;
metrics.bulk_delay_s = bulkDelayS;

% Log-spaced output grid over the swept band only; outside it the excitation
% carried no energy and every curve here would be noise.
lo = max(band(1), fs / nfft);
hi = min(band(2), fs / 2);
if ~(hi > lo)
    return
end
grid = 2 .^ (log2(lo) : 1/perOctave : log2(hi))';
metrics.frequency_hz = grid;

magLin = obj.smooth_to_log_grid_(fax, abs(H(half)), grid, SMOOTH_FRAC_OCT, "power");
metrics.magnitude_db = 20 * log10(magLin + eps);
metrics.phase_deg = obj.smooth_to_log_grid_(fax, phaseRad, grid, SMOOTH_FRAC_OCT, "linear") * 180/pi;
metrics.minimum_phase_deg = obj.smooth_to_log_grid_(fax, phaseMinRad, grid, SMOOTH_FRAC_OCT, "linear") * 180/pi;
metrics.excess_phase_deg = metrics.phase_deg - metrics.minimum_phase_deg;

gd = obj.smooth_to_log_grid_(fax, gdSamples, grid, SMOOTH_FRAC_OCT, "linear") / fs + bulkDelayS;
gdMin = obj.smooth_to_log_grid_(fax, gdMinSamples, grid, SMOOTH_FRAC_OCT, "linear") / fs;
metrics.group_delay_seconds = gd;
metrics.group_delay_samples = gd * fs;
metrics.excess_group_delay_seconds = gd - gdMin;

% Phase delay: the delay a steady sinusoid at this frequency experiences,
% as opposed to the delay of its envelope.
metrics.phase_delay_seconds = -(metrics.phase_deg * pi/180) ./ max(2*pi*grid, eps) + bulkDelayS;

ref = mean(metrics.magnitude_db, 'omitnan');
metrics.magnitude_deviation_db = metrics.magnitude_db - ref;
metrics.flatness_std_db = std(metrics.magnitude_db, 'omitnan');
metrics.magnitude_ripple_db = max(metrics.magnitude_db) - min(metrics.magnitude_db);
metrics.group_delay_variation_s = max(gd) - min(gd);
end
