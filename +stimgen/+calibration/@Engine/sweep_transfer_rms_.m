function m = sweep_transfer_rms_(obj, x, y, freqs, fs)
% m = sweep_transfer_rms_(obj, x, y, freqs, fs)
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
% Parameters:
%   x     - (1,:) double excitation waveform in volts
%   y     - (1,:) double recorded response
%   freqs - (1,:) double frequencies to sample in Hz
%   fs    - (1,1) double sample rate in Hz
%
% Returns:
%   m - (1,:) double equivalent steady-tone RMS at each freqs, in mic volts

% Kirkeby regularization. Outside the swept band |X| falls to zero and an
% unregularized Y./X amplifies noise without bound.
REG_FACTOR      = 1e-6;
SMOOTH_FRAC_OCT = 12;

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

r = 2 ^ (1 / (2 * SMOOTH_FRAC_OCT));
m = nan(1, numel(freqs));
for i = 1:numel(freqs)
    band = fax >= freqs(i) / r & fax <= freqs(i) * r;
    if any(band)
        mag = sqrt(mean(Hpow(band)));
    else
        % Smoothing band narrower than one bin: use the nearest bin.
        [~, k] = min(abs(fax - freqs(i)));
        mag = sqrt(Hpow(k));
    end
    m(i) = mag * obj.ExcitationVoltage / sqrt(2);
end
end
