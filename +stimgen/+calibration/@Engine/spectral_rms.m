function r = spectral_rms(x, freq, fs, options)
% r = stimgen.calibration.Engine.spectral_rms(x, freq, fs)
% r = stimgen.calibration.Engine.spectral_rms(x, freq, fs, Spectral=s)
% Estimate signal power at a single frequency via periodogram.
% Uses a 1/8-octave band centred on the nearest bin to freq.
%
% The default window and transform length -- flat top over the next power of
% two -- are what an unconfigured engine measures with. Spectral overrides
% either; Engine methods pass their engine's spectral_options so a run
% measures with what the user set, and an external caller reproducing a
% measurement must pass the same options the run used.
%
% Parameters:
%   x        - (1,:) double time-domain signal
%   freq     - double centre frequency in Hz
%   fs       - double sample rate in Hz
%   Spectral - (1,1) stimgen.calibration.SpectralOptions
%
% Returns:
%   r - double RMS amplitude at freq (volts)
arguments
    x
    freq
    fs
    options.Spectral (1,1) stimgen.calibration.SpectralOptions = ...
        stimgen.calibration.SpectralOptions()
end
n = numel(x);
w = options.Spectral.taper(n, "flattop");
nfft = options.Spectral.transform_length(2^nextpow2(n));
[pxx, f] = periodogram(x, w, nfft, fs, 'power');
[~, cidx] = min((f - freq).^2);
band = f >= f(cidx) * 2^(-1/8) & f <= f(cidx) * 2^(1/8);
[~, lidx] = max(pxx(band));
idx = find(band);
r = sqrt(pxx(idx(lidx)));
end
