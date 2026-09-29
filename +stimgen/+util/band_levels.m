function b = band_levels(pxx, f, df, fraction, fMin, fMax)
% b = stimgen.util.band_levels(pxx, f, df, fraction, fMin, fMax)
% Power in IEC 61260 base-ten fractional-octave bands, integrated from a PSD.
%
% The band arithmetic only: centres, edges, and the power each band holds, in
% the squared units of the PSD it was given. Turning that power into a level
% is the caller's business, because the scale is: a calibrated caller goes
% through stimgen.calibration.Engine.volts_to_spl, an uncalibrated one takes
% 10*log10. It was a local function of Engine/analyze_background_ until
% stimgen.StimInspector needed band levels as well, and sharing it is what
% makes a band in the background analysis and a band in the inspector the
% same band.
%
% Centres follow IEC 61260-1's base-ten series, fc = 1000 * G^(k/fraction)
% with G = 10^(3/10), so a third-octave band is centred on 1000, 1259, 1585
% Hz and so on -- the exact values behind the nominal 1k, 1.25k, 1.6k.
%
% A band reaching past fMax, or whose lower edge is below fMin, is dropped
% rather than reported: the part of it that was measured would be read as
% though it were the whole. fMin is where the caller decides the spectrum
% stops resolving a band -- a few resolution cells, typically -- since below
% that a "band level" is one bin with a band's name on it. A band that holds
% no bin of f at all is dropped for the same reason.
%
% Parameters:
%   pxx      - power spectral density (units^2/Hz), one-sided, on f
%   f        - frequency of each pxx bin (Hz), ascending
%   df       - bin spacing of f (Hz), the width each bin integrates over
%   fraction - bands per octave: 1, 3, 6, 12, ...
%   fMin     - lowest lower band edge that may be reported (Hz)
%   fMax     - highest upper band edge that may be reported (Hz)
%
% Returns:
%   b - struct:
%     frequency - (1,n) exact band centres (Hz)
%     power     - (1,n) power in each band (units^2), sum(pxx) * df over it
%     edges     - (2,n) lower and upper band edges (Hz)
%     fraction  - bands per octave, as given
%
% Example:
%   [pxx, f] = periodogram(y, hann(numel(y)), [], fs);
%   b = stimgen.util.band_levels(pxx, f, f(2) - f(1), 3, 20, fs/2);
%   lvl = 10*log10(b.power);             % dB re 1 unit^2 per band
%
% See also: stimgen.util.weighting_db, stimgen.StimInspector
arguments
    pxx      (:,1) double
    f        (:,1) double
    df       (1,1) double {mustBePositive}
    fraction (1,1) double {mustBePositive}
    fMin     (1,1) double {mustBeNonnegative}
    fMax     (1,1) double {mustBePositive}
end

G    = 10 ^ (3 / 10);
kLo  = ceil(fraction  * log(max(fMin, realmin) / 1000) / log(G));
kHi  = floor(fraction * log(fMax / 1000) / log(G));
fc   = 1000 .* G .^ ((kLo:kHi) ./ fraction);
half = G ^ (1 / (2 * fraction));
flo  = fc ./ half;
fhi  = fc .* half;

keep = flo >= fMin & fhi <= fMax;
fc = fc(keep); flo = flo(keep); fhi = fhi(keep);

n   = numel(fc);
pwr = nan(1, n);
for k = 1:n
    m = f >= flo(k) & f < fhi(k);
    if any(m)
        pwr(k) = sum(pxx(m)) * df;
    end
end

ok = ~isnan(pwr);
b = struct( ...
    'frequency', fc(ok), ...
    'power',     pwr(ok), ...
    'edges',     [flo(ok); fhi(ok)], ...
    'fraction',  fraction);
end
