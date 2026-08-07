function results = analyze_background_(obj, records, fs, options)
% results = analyze_background_(obj, records, fs, options)
% Turn one or more silent recordings into the background analysis stored in
% CalibrationData.background.
%
% Three questions are being answered, and each needs a different reduction of
% the same records:
%   how loud is it        - broadband level, unweighted and A-weighted, on the
%                           scale the reference measurement established;
%   where is it           - fractional-octave band levels, which is the form a
%                           noise floor is comparable in and the form it has to
%                           be in to be read against a stimulus spectrum;
%   what is it            - discrete tonal components standing above the local
%                           floor, since mains hum and a switching supply are
%                           fixable in a way that broadband hiss is not.
%
% Records are power-averaged, not concatenated: averaging spectra across
% separate captures smooths the estimator without pretending the captures were
% contiguous, and it leaves the per-record levels available as the evidence
% that the room held still while it was measured.
%
% Parameters:
%   records - (1,:) cell of (1,:) double silent recordings (V)
%   fs      - (1,1) double sample rate (Hz)
%   options - struct of the Name-Value options measure_background collected
%
% Returns:
%   results - struct:
%     duration_s, repeat_count, fs, measuredOn
%     spl_db, spl_dba          - broadband level, unweighted and A-weighted
%     repeat_spl_db            - (1,R) level of each record
%     sd_db, range_db, stable  - spread across records, and the verdict on it
%     rms_v, peak_v            - across-record RMS and worst peak
%     crest_factor_db          - peak over RMS; a large value means the record
%                                is dominated by transients, not a steady floor
%     dc_offset_v              - mean of each record, removed before analysis
%     headroom_db, clipping    - margin to MaxOutputVoltage, and whether the
%                                record reached it
%     distinct_levels          - unique sample values in the quietest record;
%                                a handful means the input is quantizer-limited
%                                and the "noise floor" is the converter's
%     bands                    - struct: frequency, level_db, level_dba,
%                                snr_at_normative_db, edges, fraction
%     spectrum                 - struct: frequency, level_db at 1/12 octave,
%                                for drawing after the raw record is gone
%     peaks                    - struct: frequency, level_db, prominence_db
%     mains                    - struct: frequency, n_harmonics, level_db
%     worst_band               - struct: frequency, level_db of the loudest band
%     normative_value_db, headroom_to_normative_db
%     reference_level_db, mic_sensitivity - the scale the levels are on
%     flags                    - (1,:) string of findings worth acting on
%
% See also: stimgen.calibration.Engine/measure_background
arguments
    obj
    records (1,:) cell
    fs      (1,1) double {mustBePositive, mustBeFinite}
    options (1,1) struct
end

nRep    = numel(records);
micSens = max(obj.MicSensitivity, eps);
refLvl  = obj.ReferenceLevel;

% --- Time-domain measures, one per record ---------------------------------
% DC is an offset in the acquisition path, not sound. It is removed before
% anything is measured -- it would otherwise inflate every level it entered --
% and reported on its own, because a drifting input is a fault worth seeing.
dcOffset = nan(1, nRep);
rmsV     = nan(1, nRep);
peakV    = nan(1, nRep);
nLevels  = inf;
for k = 1:nRep
    y = records{k};
    dcOffset(k) = mean(y);
    y = y - dcOffset(k);
    records{k} = y;

    rmsV(k)  = sqrt(mean(y .^ 2));
    peakV(k) = max(abs(y));
    nLevels  = min(nLevels, numel(unique(records{k})));
end

% Clipping is judged against the converter ceiling alone. estimate_headroom_'s
% flat-top test cannot be used here: a record sitting a few LSBs above zero
% spends most of its samples at its own peak, which that test reads as a
% clipped waveform when it is the opposite problem.
fullScaleV  = obj.MaxOutputVoltage;
peakAll     = max(peakV);
clipping    = peakAll >= fullScaleV * 0.999;
headroomDb  = 20 * log10(max(fullScaleV, eps) / max(peakAll, eps));

rmsAll    = sqrt(mean(rmsV .^ 2));   % power-average, not level-average
splAll    = refLvl + 20 * log10(rmsAll ./ micSens);
repeatSpl = refLvl + 20 * log10(rmsV ./ micSens);
rangeDb   = max(repeatSpl) - min(repeatSpl);

% --- Averaged power spectrum ----------------------------------------------
[pxx, f] = welch_average_(records, fs);
df = f(2) - f(1);

% --- Broadband A-weighted level -------------------------------------------
% Integrated over the weighted spectrum rather than by filtering the record:
% the spectrum is already averaged, and the weighting is exact on it. The DC
% bin contributes nothing -- the weighting is zero there by construction.
aw     = stimgen.util.weighting_db(f, "A");
powA   = sum(pxx .* 10 .^ (aw ./ 10)) * df;
splA   = refLvl + 10 * log10(max(powA, realmin)) - 20 * log10(micSens);

% --- Fractional-octave band levels ----------------------------------------
% The lowest usable band is the one wide enough to hold a few FFT bins; below
% that a "band level" is one bin with a band's name on it.
fMin = max(5 * df, 10);
bands = band_levels_(pxx, f, df, options.FractionalOctave, fMin, fs / 2, refLvl, micSens);
bands.snr_at_normative_db = obj.NormativeValue - bands.level_db;
bands.level_dba = bands.level_db + stimgen.util.weighting_db(bands.frequency, "A");

worstBand = struct('frequency', nan, 'level_db', nan);
if ~isempty(bands.level_db)
    [wl, wi] = max(bands.level_db);
    worstBand.frequency = bands.frequency(wi);
    worstBand.level_db  = wl;
end

% A finer band set is kept for drawing. The raw record is not saved in the
% .esgc, so without this the analysis could never be redrawn from a loaded
% file -- only the numbers would survive.
spectrum = band_levels_(pxx, f, df, 12, fMin, fs / 2, refLvl, micSens);
spectrum = rmfield(spectrum, {'edges', 'fraction'});

% --- Tonal components ------------------------------------------------------
peaks = tonal_peaks_(pxx, f, df, fs, refLvl, micSens, ...
    options.TonalProminenceDb, options.MaxPeaks);
mains = mains_components_(peaks, df);

% --- Findings --------------------------------------------------------------
flags = strings(1, 0);
if clipping
    flags(end+1) = sprintf(['The record reached the %g V full-scale limit. The level ' ...
        'below is a floor, not a measurement -- reduce input gain and repeat.'], fullScaleV);
end
if nLevels < 64
    flags(end+1) = sprintf(['Only %d distinct sample values in the quietest record: the ' ...
        'input is at its quantization floor, so this measures the converter rather than ' ...
        'the room. Raise input gain and repeat.'], nLevels);
end
if nRep > 1 && rangeDb > options.StabilityToleranceDb
    flags(end+1) = sprintf(['Level varied %.1f dB across the %d records (tolerance %.1f dB). ' ...
        'Something intermittent is in the room; a single number will not describe it.'], ...
        rangeDb, nRep, options.StabilityToleranceDb);
end
if isfinite(mains.frequency)
    flags(end+1) = sprintf(['Mains-related tones at %g Hz and %d harmonic(s), %.1f dB SPL ' ...
        'combined. This is a grounding or shielding problem, not a room problem.'], ...
        mains.frequency, mains.n_harmonics, mains.level_db);
end
headroomToNormative = obj.NormativeValue - splAll;
if headroomToNormative < 40
    flags(end+1) = sprintf(['Background is %.1f dB below the %g dB SPL normative level. ' ...
        'Quiet stimuli will not be clear of it.'], headroomToNormative, obj.NormativeValue);
end
maxCrest = 20 * log10(max(peakV ./ max(rmsV, eps)));
if maxCrest > 20
    flags(end+1) = sprintf(['Crest factor %.0f dB: the record is dominated by transients ' ...
        'rather than a steady floor, so the broadband level depends on when it was taken.'], ...
        maxCrest);
end

% --- Result ----------------------------------------------------------------
results = struct();
results.duration_s   = numel(records{1}) / fs;
results.repeat_count = nRep;
results.fs           = fs;
results.measuredOn   = datetime('now');

results.spl_db        = splAll;
results.spl_dba       = splA;
results.repeat_spl_db = repeatSpl;
results.sd_db         = std(repeatSpl);
results.range_db      = rangeDb;
results.stable        = nRep < 2 || rangeDb <= options.StabilityToleranceDb;

results.rms_v           = rmsAll;
results.peak_v          = peakAll;
results.crest_factor_db = maxCrest;
results.dc_offset_v     = dcOffset;
results.headroom_db     = headroomDb;
results.clipping        = clipping;
results.distinct_levels = nLevels;

results.bands      = bands;
results.spectrum   = spectrum;
results.peaks      = peaks;
results.mains      = mains;
results.worst_band = worstBand;

results.normative_value_db        = obj.NormativeValue;
results.headroom_to_normative_db  = headroomToNormative;
results.reference_level_db        = refLvl;
results.mic_sensitivity           = obj.MicSensitivity;

results.tonal_prominence_db = options.TonalProminenceDb;
results.flags               = flags;
end

% ------------------------------------------------------------------------ %
function [pxx, f] = welch_average_(records, fs)
% Power-averaged Welch spectrum over every record, on one frequency axis.
%
% The window is sized for a few hertz of resolution -- fine enough to separate
% a mains harmonic from the floor it sits on -- but never more than a quarter
% of the shortest record, so even a brief capture is averaged over several
% segments instead of being one noisy periodogram.
nMin = min(cellfun(@numel, records));

nwin = 2 ^ nextpow2(fs / 4);
nwin = min(nwin, 2 ^ floor(log2(max(nMin / 4, 256))));
nwin = max(min(nwin, nMin), 8);
nfft = max(nwin, 256);

pxx = [];
f   = [];
for k = 1:numel(records)
    [p, fv] = pwelch(records{k}, hann(nwin, 'periodic'), floor(nwin / 2), nfft, fs, 'psd');
    if isempty(pxx)
        pxx = p(:);
        f   = fv(:);
    else
        pxx = pxx + p(:);
    end
end
pxx = pxx ./ numel(records);
end

% ------------------------------------------------------------------------ %
function b = band_levels_(pxx, f, df, frac, fMin, fMax, refLvl, micSens)
% Integrate the PSD over IEC 61260 base-ten fractional-octave bands.
G    = 10 ^ (3 / 10);
kLo  = ceil(frac  * log(fMin / 1000) / log(G));
kHi  = floor(frac * log(fMax / 1000) / log(G));
fc   = 1000 .* G .^ ((kLo:kHi) ./ frac);
half = G ^ (1 / (2 * frac));
flo  = fc ./ half;
fhi  = fc .* half;

% A band reaching past Nyquist, or below where the FFT can resolve it, would
% report the part of itself that was measured as though it were the whole.
keep = flo >= fMin & fhi <= fMax;
fc = fc(keep); flo = flo(keep); fhi = fhi(keep);

n   = numel(fc);
lvl = nan(1, n);
for k = 1:n
    m = f >= flo(k) & f < fhi(k);
    if ~any(m)
        continue
    end
    lvl(k) = refLvl + 10 * log10(max(sum(pxx(m)) * df, realmin)) - 20 * log10(micSens);
end

ok = isfinite(lvl);
b = struct( ...
    'frequency', fc(ok), ...
    'level_db',  lvl(ok), ...
    'edges',     [flo(ok); fhi(ok)], ...
    'fraction',  frac);
end

% ------------------------------------------------------------------------ %
function p = tonal_peaks_(pxx, f, df, fs, refLvl, micSens, promDb, maxPeaks)
% Narrowband components standing above the local spectral floor.
%
% Prominence is measured against a running median rather than an absolute
% threshold: a real noise floor slopes, often steeply at the low end, and any
% fixed level either misses hum on a sloping floor or calls the whole low end
% tonal. The median is taken over a span wide enough that a line and its skirt
% cannot move it.
p = struct('frequency', [], 'level_db', [], 'prominence_db', []);
if maxPeaks < 1
    return
end

pxxDb = 10 * log10(max(pxx, realmin));
nMed  = 2 * round(max(25, 50 / df)) + 1;
if nMed >= numel(pxxDb)
    return
end
excess = pxxDb - movmedian(pxxDb, nMed, 'omitnan');

% Below a few bins the estimate is the window's own leakage; the very top of
% the band is the anti-alias filter's roll-off, not a tone.
usable = find(f >= max(10, 3 * df) & f <= 0.98 * fs / 2);
if numel(usable) < 8
    return
end

[~, loc] = findpeaks(excess(usable), MinPeakHeight=promDb, MinPeakDistance=3);
if isempty(loc)
    return
end
idx = usable(loc);

[~, order] = sort(excess(idx), 'descend');
idx = idx(order(1:min(maxPeaks, numel(order))));

% A line occupies more than one bin once windowed, so its level is the power in
% the bins around the peak, not the peak bin alone. Its frequency comes from a
% quadratic fit through the peak instead of the bin centre: a line almost never
% lands on one, and at a few hertz per bin the difference is what separates
% "60 Hz mains" from "58.6 Hz, something".
lvl  = nan(1, numel(idx));
fRef = nan(1, numel(idx));
for k = 1:numel(idx)
    span = max(idx(k) - 2, 1) : min(idx(k) + 2, numel(pxx));
    lvl(k)  = refLvl + 10 * log10(max(sum(pxx(span)) * df, realmin)) - 20 * log10(micSens);
    fRef(k) = refine_peak_(pxxDb, f, idx(k), df);
end

[fpk, order] = sort(fRef);   % report in frequency order; ranking is done above
p.frequency     = fpk;
p.level_db      = lvl(order);
p.prominence_db = excess(idx(order)).';
end

% ------------------------------------------------------------------------ %
function fPk = refine_peak_(pxxDb, f, i, df)
% Sub-bin peak frequency by fitting a parabola through the peak bin and its
% neighbours in dB. Exact for a Gaussian-shaped peak, which a windowed line
% approximates well enough at this resolution.
fPk = f(i);
if i <= 1 || i >= numel(pxxDb)
    return
end
a = pxxDb(i-1);
b = pxxDb(i);
c = pxxDb(i+1);
den = a - 2*b + c;
if den == 0 || ~isfinite(den)
    return
end
delta = 0.5 * (a - c) / den;
if ~isfinite(delta) || abs(delta) > 1
    return   % the fit put the peak outside the bracket; the bin is the better answer
end
fPk = f(i) + delta * df;
end

% ------------------------------------------------------------------------ %
function m = mains_components_(peaks, df)
% Which line frequency, if either, explains the tonal peaks.
%
% Worth separating from the rest: hum is the one background component that is
% almost always the rig's own wiring rather than the room, and it is fixed by
% grounding rather than by acoustic treatment.
m = struct('frequency', nan, 'n_harmonics', 0, 'level_db', nan);
if isempty(peaks.frequency)
    return
end

% Half a bin, which the sub-bin peak refinement comfortably resolves. A looser
% window is what lets 50 and 60 Hz both "explain" the same harmonic series on a
% short record, where the bins are wide -- and then the wrong one can win.
tol = max(0.5 * df, 1);

best     = m;
bestMiss = inf;
for f0 = [50 60]
    harmonics = f0 .* (1:12);
    miss = nan(1, numel(peaks.frequency));
    for k = 1:numel(peaks.frequency)
        miss(k) = min(abs(peaks.frequency(k) - harmonics));
    end
    hit = miss <= tol;
    if ~any(hit)
        continue
    end

    meanMiss = mean(miss(hit));
    % More harmonics explained wins; a tie goes to the series the peaks sit
    % closer to, not to whichever was tried first.
    better = nnz(hit) > best.n_harmonics || ...
        (nnz(hit) == best.n_harmonics && meanMiss < bestMiss);
    if better
        best = struct('frequency', f0, 'n_harmonics', nnz(hit), ...
            'level_db', 10 * log10(sum(10 .^ (peaks.level_db(hit) ./ 10))));
        bestMiss = meanMiss;
    end
end
m = best;
end
