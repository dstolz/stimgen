function [H, freqHz, h, nfft] = deconvolve_sweep_(~, x, y, fs)
% [H, freqHz, h, nfft] = deconvolve_sweep_(obj, x, y, fs)
% Regularized deconvolution of one swept-sine excitation/response pair.
%
% The impulse response is returned circular, not truncated: a log sweep places
% the N-th harmonic distortion product a fixed interval *before* the linear
% impulse response, so those products wrap into the tail of h instead of being
% thrown away. estimate_sweep_harmonics_ reads them there, which is the whole
% reason a log sweep is worth measuring with.
%
% Parameters:
%   x  - (:,1) double excitation waveform in volts
%   y  - (:,1) double recorded response
%   fs - (1,1) double sample rate in Hz
%
% Returns:
%   H      - (nfft,1) complex two-sided transfer function
%   freqHz - (floor(nfft/2)+1,1) double one-sided frequency axis in Hz
%   h      - (nfft,1) double circular impulse response
%   nfft   - (1,1) double transform length

% Kirkeby regularization. |X| falls to zero outside the swept band, where an
% unregularized Y./X amplifies the noise floor without bound.
REG_FACTOR = 1e-6;

x = x(:);
y = y(:);

% Full linear-convolution length, so the reverberant tail does not fold back
% onto the direct sound. The harmonic products still wrap, by design.
nfft = 2 ^ nextpow2(numel(x) + numel(y));

X = fft(x, nfft);
Y = fft(y, nfft);
Xpow = abs(X) .^ 2;
H = (Y .* conj(X)) ./ (Xpow + REG_FACTOR * mean(Xpow));

freqHz = (0:floor(nfft/2))' .* (fs / nfft);
h = real(ifft(H));
end
