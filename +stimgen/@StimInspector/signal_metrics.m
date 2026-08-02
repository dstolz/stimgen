function M = signal_metrics(y, fs, nHarmonics)
% M = stimgen.StimInspector.signal_metrics(y, fs)
% M = stimgen.StimInspector.signal_metrics(y, fs, nHarmonics)
% Measure the time-domain, spectral and distortion properties of a waveform.
%
% All measurements are made on the waveform as given; amplitudes are relative
% to full scale (1.0), so a calibrated signal scaled to volts reads in dBV
% rather than dBFS.  The single-sided magnitude spectrum is computed with a
% Hann window and corrected for its coherent gain, so a full-scale sinusoid
% reads 0 dB at its own frequency.
%
% Parameters:
%   y          - Waveform vector (row or column).
%   fs         - Sample rate in Hz.
%   nHarmonics - Harmonics included in the THD estimate (default 6).
%
% Returns:
%   M - Metrics struct.  M.Valid is false when the waveform is too short,
%       constant or non-finite, in which case every measurement is NaN.
%       Fields include:
%         N, DurationMs, Fs
%         Peak, PeakToPeak, RMS, DC, PeakDb, RmsDb, CrestFactorDb
%         Freq, MagDb            - single-sided spectrum for plotting
%         Envelope               - analytic-signal envelope ([] if not computed)
%         FundamentalHz, FundamentalDb, Tonality, Tonal
%         CentroidHz, RmsBandwidthHz, Flatness, Band3dB, Band20dB
%         ThdDb, ThdPercent, HarmonicHz, HarmonicDb
%         SnrDb, SinadDb, SfdrDb
%
% See also: thd, snr, sinad, sfdr

if nargin < 3 || isempty(nHarmonics)
    nHarmonics = 6;
end
if isempty(fs) || ~isfinite(fs) || fs <= 0
    fs = 1;
end

y = double(y(:)).';
n = numel(y);

M = struct( ...
    'Fs',             fs, ...
    'N',              n, ...
    'DurationMs',     n / fs * 1e3, ...
    'Valid',          false, ...
    'Peak',           NaN, ...
    'PeakToPeak',     NaN, ...
    'RMS',            NaN, ...
    'DC',             NaN, ...
    'PeakDb',         NaN, ...
    'RmsDb',          NaN, ...
    'CrestFactorDb',  NaN, ...
    'Freq',           [], ...
    'MagDb',          [], ...
    'Envelope',       [], ...
    'FundamentalHz',  NaN, ...
    'FundamentalDb',  NaN, ...
    'Tonality',       NaN, ...
    'Tonal',          false, ...
    'CentroidHz',     NaN, ...
    'RmsBandwidthHz', NaN, ...
    'Flatness',       NaN, ...
    'Band3dB',        [NaN NaN], ...
    'Band20dB',       [NaN NaN], ...
    'ThdDb',          NaN, ...
    'ThdPercent',     NaN, ...
    'HarmonicHz',     [], ...
    'HarmonicDb',     [], ...
    'SnrDb',          NaN, ...
    'SinadDb',        NaN, ...
    'SfdrDb',         NaN);

if n < 8 || ~all(isfinite(y)) || ~any(y ~= 0)
    return
end
M.Valid = true;

% --- Time domain -----------------------------------------------------
M.Peak          = max(abs(y));
M.PeakToPeak    = max(y) - min(y);
M.RMS           = sqrt(mean(y.^2));
M.DC            = mean(y);
M.PeakDb        = 20*log10(M.Peak);
M.RmsDb         = 20*log10(max(M.RMS, eps));
M.CrestFactorDb = M.PeakDb - M.RmsDb;

% The analytic signal costs an FFT pair over the whole waveform; skip it for
% very long signals rather than stalling the GUI.
if n <= 2^22
    try
        M.Envelope = abs(hilbert(y));
    catch
        M.Envelope = [];
    end
end

% --- Magnitude spectrum ----------------------------------------------
% Hann window, scaled so a full-scale sinusoid peaks at 0 dB.
w    = hann(n).';
nfft = 2^nextpow2(max(n, 1024));
Y    = fft(y .* w, nfft);
half = floor(nfft/2) + 1;

mag       = abs(Y(1:half)) * (2 / sum(w));
mag(1)    = mag(1) / 2;               % DC is not mirrored
if mod(nfft, 2) == 0
    mag(half) = mag(half) / 2;        % neither is Nyquist
end

f       = (0:half-1) * (fs / nfft);
M.Freq  = f;
M.MagDb = 20*log10(max(mag, eps));

% --- Fundamental ------------------------------------------------------
% Ignore bins below one full-length resolution cell so a DC offset or a slow
% envelope term is not mistaken for the fundamental.
minIdx = find(f >= fs/n, 1);
if isempty(minIdx) || minIdx < 2
    minIdx = 2;
end
if minIdx > half
    minIdx = half;
end

[peakMag, k] = max(mag(minIdx:end));
k = k + minIdx - 1;
M.FundamentalHz = f(k);
M.FundamentalDb = 20*log10(max(peakMag, eps));

% Parabolic interpolation across the peak refines the frequency estimate to
% well under one bin for tonal signals.
if k > 1 && k < half
    a = M.MagDb(k-1);
    b = M.MagDb(k);
    c = M.MagDb(k+1);
    denom = a - 2*b + c;
    if denom ~= 0
        delta = 0.5 * (a - c) / denom;
        if isfinite(delta) && abs(delta) < 1
            M.FundamentalHz = f(k) + delta * (fs / nfft);
        end
    end
end

% --- Spectral shape ---------------------------------------------------
p    = mag.^2;
p(1) = 0;                       % exclude DC from spectral shape statistics
totalPower = sum(p);

if totalPower > 0
    M.CentroidHz     = sum(f .* p) / totalPower;
    M.RmsBandwidthHz = sqrt(sum((f - M.CentroidHz).^2 .* p) / totalPower);

    pos        = p(2:end);
    M.Flatness = exp(mean(log(pos + eps))) / mean(pos + eps);

    % Fraction of the total power within a few resolution cells of the peak:
    % ~1 for a pure tone, small for anything broadband.
    nearPeak   = abs(f - f(k)) <= 4 * fs / n;
    M.Tonality = sum(p(nearPeak)) / totalPower;
    M.Tonal    = M.Tonality > 0.5;

    M.Band3dB  = level_band_(f, M.MagDb, minIdx, 3);
    M.Band20dB = level_band_(f, M.MagDb, minIdx, 20);
end

% --- Distortion and noise --------------------------------------------
% These estimators all assume a dominant sinusoid.  They are reported for
% every stimulus, but only mean what their names say when M.Tonal is true.
try
    [thdDb, harmPow, harmFreq] = thd(y(:), fs, nHarmonics);
    M.ThdDb      = thdDb;
    M.ThdPercent = 100 * 10^(thdDb/20);
    M.HarmonicHz = harmFreq(:).';
    M.HarmonicDb = harmPow(:).';
catch
    % Leave the distortion fields at NaN when no fundamental can be resolved.
end

try
    M.SnrDb = snr(y(:), fs);
catch
end

try
    M.SinadDb = sinad(y(:), fs);
catch
end

try
    M.SfdrDb = sfdr(y(:), fs);
catch
end
end % signal_metrics


% =========================================================================

function band = level_band_(f, magDb, minIdx, dropDb)
% level_band_(f, magDb, minIdx, dropDb) - Outermost frequencies within dropDb of the peak.
band = [NaN NaN];
inBand = false(size(magDb));
inBand(minIdx:end) = magDb(minIdx:end) >= max(magDb(minIdx:end)) - dropDb;
idx = find(inBand);
if ~isempty(idx)
    band = [f(idx(1)) f(idx(end))];
end
end
