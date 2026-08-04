function [f, lvl] = spectrum_db_spl_(y, fs, refLevel, micSens, nBins)
% [f, lvl] = spectrum_db_spl_(y, fs, refLevel, micSens, nBins)
% Magnitude spectrum of a response record, in dB SPL, thinned onto a log
% frequency grid for display.
%
% Short records get the same flat-top periodogram the engine measures with, so
% the displayed peak agrees with the number written into the LUT. Long records
% -- a swept sine is seconds long -- get Welch instead: a single periodogram of
% a 100k-sample record costs more per redraw than the whole live update budget,
% and its bin-level detail is thrown away by the log grid regardless.
%
% Thinning is peak-hold, not averaging or subsampling: a tone occupies one bin
% out of tens of thousands, and any other reduction loses it.
%
% Parameters:
%   y        - (1,:) double response record (V)
%   fs       - (1,1) double sample rate (Hz)
%   refLevel - (1,1) double reference level (dB SPL)
%   micSens  - (1,1) double microphone sensitivity (V/Pa)
%   nBins    - (1,1) double log-grid bins to return
%
% Returns:
%   f   - (1,:) double frequency (Hz)
%   lvl - (1,:) double level (dB SPL)

n = numel(y);
WELCH_THRESHOLD = 2^15;

if n > WELCH_THRESHOLD
    nseg = 2^13;
    [pxx, fv] = pwelch(y, hann(nseg), nseg/2, 2^14, fs, 'power');
else
    [pxx, fv] = periodogram(y, flattopwin(n), 2^nextpow2(n), fs, 'power');
end

lvlFull = refLevel + 20 * log10(max(sqrt(pxx(:).'), eps) ./ max(micSens, eps));
fv = fv(:).';

% Drop DC: it has no place on a log axis and is not a level anyone reads.
keep = fv > 0;
fv = fv(keep);
lvlFull = lvlFull(keep);

if isempty(fv)
    f = [];
    lvl = [];
    return
end
if numel(fv) <= nBins
    f = fv;
    lvl = lvlFull;
    return
end

lo = max(fv(1), 1);
hi = fv(end);
edges = logspace(log10(lo), log10(hi), nBins + 1);
bin = discretize(fv, edges);

ok = ~isnan(bin);
lvl = accumarray(bin(ok).', lvlFull(ok).', [nBins 1], @max, NaN).';
f = sqrt(edges(1:end-1) .* edges(2:end));

occupied = ~isnan(lvl);
f = f(occupied);
lvl = lvl(occupied);
end
