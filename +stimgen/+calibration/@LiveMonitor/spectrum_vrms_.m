function [f, vrms, noiseBw] = spectrum_vrms_(y, fs, nBins)
% [f, vrms, noiseBw] = spectrum_vrms_(y, fs, nBins)
% Magnitude spectrum of a response record as rms volts per bin, thinned onto a
% log frequency grid for display, plus the equivalent noise bandwidth of the
% analysis window.
%
% Volts, not a level: every unit the spectrum panel offers is a monotone
% function of the measured voltage, so thinning here and converting at draw
% time gives the same curve as converting first, and one measurement serves
% whichever unit is selected -- including the ghost of a record that was
% acquired before the unit was changed.
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
% noiseBw is the window's equivalent noise bandwidth, which is what turns a
% per-bin level into a per-Hz density; it depends on the window, not on the
% record, so the density units stay comparable across the two branches only
% insofar as this number is carried with the curve.
%
% Parameters:
%   y     - (1,:) double response record (V)
%   fs    - (1,1) double sample rate (Hz)
%   nBins - (1,1) double log-grid bins to return
%
% Returns:
%   f       - (1,:) double frequency (Hz)
%   vrms    - (1,:) double magnitude (V rms per bin)
%   noiseBw - (1,1) double equivalent noise bandwidth of the window (Hz)

n = numel(y);
WELCH_THRESHOLD = 2^15;

if n > WELCH_THRESHOLD
    nseg = 2^13;
    win = hann(nseg);
    [pxx, fv] = pwelch(y, win, nseg/2, 2^14, fs, 'power');
else
    win = flattopwin(n);
    [pxx, fv] = periodogram(y, win, 2^nextpow2(n), fs, 'power');
end
noiseBw = enbw(win, fs);

vrmsFull = max(sqrt(pxx(:).'), eps);
fv = fv(:).';

% Drop DC: it has no place on a log axis and is not a level anyone reads.
keep = fv > 0;
fv = fv(keep);
vrmsFull = vrmsFull(keep);

if isempty(fv)
    f = [];
    vrms = [];
    return
end
if numel(fv) <= nBins
    f = fv;
    vrms = vrmsFull;
    return
end

lo = max(fv(1), 1);
hi = fv(end);
edges = logspace(log10(lo), log10(hi), nBins + 1);
bin = discretize(fv, edges);

ok = ~isnan(bin);
vrms = accumarray(bin(ok).', vrmsFull(ok).', [nBins 1], @max, NaN).';
f = sqrt(edges(1:end-1) .* edges(2:end));

occupied = ~isnan(vrms);
f = f(occupied);
vrms = vrms(occupied);
end
