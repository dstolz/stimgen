function fc = spectral_centroid(y, fs)
% fc = stimgen.util.spectral_centroid(y, fs)
% Power-weighted mean frequency of a waveform.
%
% Used as a calibration LUT anchor when a stimulus has no single defining
% frequency (stimgen.SoundFile in "Direct" mode, stimgen.Patch in "Tone" mode
% with AnchorFrequency = 0).
%
% Parameters:
%   y  - waveform (vector)
%   fs - sample rate in Hz
%
% Returns:
%   fc - centroid frequency in Hz, or NaN when undefined. Callers pass NaN
%        through to the calibration Engine, which falls back to its
%        ReferenceFrequency.

n = numel(y);
if n < 2
    fc = NaN;
    return
end

nfft = 2^nextpow2(n);
Y    = abs(fft(y, nfft));
half = floor(nfft/2) + 1;
p    = reshape(Y(1:half), [], 1).^2;
f    = (0:half-1)' .* (fs / nfft);

total = sum(p);
if ~isfinite(total) || total <= 0
    fc = NaN;
    return
end

fc = sum(f .* p) ./ total;
if ~isfinite(fc) || fc <= 0
    fc = NaN;
end
end
