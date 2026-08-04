function m = sweep_transfer_rms_(obj, x, y, freqs, fs, band)
% m = sweep_transfer_rms_(obj, x, y, freqs, fs)
% m = sweep_transfer_rms_(obj, x, y, freqs, fs, band)
% Equivalent steady-tone microphone RMS at each frequency, recovered from one
% swept-sine excitation/response pair.
%
% A chirp visits each frequency for only a few milliseconds, so reading the
% response periodogram at one frequency (spectral_rms) does not measure a
% level: it lands 25-95 dB below the true steady-tone level and drops a
% further 3 dB every time the sweep duration doubles. The transfer function
% is duration-invariant. H(f) = Y(f)/X(f) is microphone volts per drive volt,
% so a steady sinusoid of peak ExcitationVoltage would measure
% |H(f)| * ExcitationVoltage / sqrt(2) -- exactly the quantity
% calibrate_tones measures directly, which puts both LUTs on one scale.
%
% |H| is power-averaged over a 1/12-octave band. Single-bin estimates are
% unbiased but noisy; the band average costs no accuracy on a smooth response
% and cuts measurement-noise error roughly tenfold at 20 dB SNR.
%
% Only bins the excitation actually drove are averaged. Where |X| collapses,
% the regularized ratio turns into noise multiplied by up to 1/(2*sqrt(lambda))
% -- 40 dB or more above its in-band gain -- and a power average is the one
% statistic that cannot ignore an outlier that large. At the top calibration
% point this matters even when nothing looks wrong: a 1/12-octave band centred
% on the sweep's stop frequency draws *half* its bins from above that stop
% frequency, so the reported level rises with the noise floor rather than with
% the transducer. That is the artefactual high-frequency lift this guard exists
% to remove; see documentation/stimgen_SweptSineCalibration.md.
%
% Parameters:
%   x     - (1,:) double excitation waveform in volts
%   y     - (1,:) double recorded response
%   freqs - (1,:) double frequencies to sample in Hz
%   fs    - (1,1) double sample rate in Hz
%   band  - (1,2) double swept band [start stop] in Hz. Averaging is confined
%           to it, since outside it the excitation carried no energy (default:
%           the whole one-sided spectrum, i.e. no confinement)
%
% Returns:
%   m - (1,:) double equivalent steady-tone RMS at each freqs, in mic volts

% Kirkeby regularization. Outside the swept band |X| falls to zero and an
% unregularized Y./X amplifies noise without bound.
REG_FACTOR      = 1e-6;
SMOOTH_FRAC_OCT = 12;

% A bin this far below the strongest excitation within the same averaging band
% is on the sweep's roll-off shoulder, not in its passband. The test is local
% because a log sweep's own spectrum tilts ~3 dB per octave, so no single
% global threshold separates the shoulder from the far end of a wide sweep.
% In-band the chirp ripples by ~1 dB, leaving an order of magnitude of margin.
EXCITATION_FLOOR_DB = 12;

x = x(:).';
y = y(:).';
nfft = 2 ^ nextpow2(2 * max(numel(x), numel(y)));

X = fft(x, nfft);
Y = fft(y, nfft);
Xpow = abs(X) .^ 2;
H = (Y .* conj(X)) ./ (Xpow + REG_FACTOR * mean(Xpow));

half = 1 : (floor(nfft/2) + 1);
fax  = (half - 1) .* (fs / nfft);
Hpow = abs(H(half)) .^ 2;
Xh   = Xpow(half);

if nargin < 6 || isempty(band)
    band = [0, fs / 2];
end
inBand = fax >= band(1) & fax <= band(2);

r = 2 ^ (1 / (2 * SMOOTH_FRAC_OCT));
floorFactor = 10 ^ (-EXCITATION_FLOOR_DB / 10);
m = nan(1, numel(freqs));
for i = 1:numel(freqs)
    band_i = fax >= freqs(i) / r & fax <= freqs(i) * r & inBand;
    if any(band_i)
        % The bin holding the max always survives, so this cannot empty the band.
        band_i = band_i & Xh >= max(Xh(band_i)) * floorFactor;
        mag = sqrt(mean(Hpow(band_i)));
    else
        % Smoothing band narrower than one bin, or entirely outside the sweep:
        % use the nearest bin the excitation drove.
        candidates = find(inBand);
        if isempty(candidates)
            candidates = 1:numel(fax);
        end
        [~, k] = min(abs(fax(candidates) - freqs(i)));
        mag = sqrt(Hpow(candidates(k)));
    end
    m(i) = mag * obj.ExcitationVoltage / sqrt(2);
end
end
