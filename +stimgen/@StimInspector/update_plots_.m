function update_plots_(obj, M)
% update_plots_(obj, M) - Redraw the visible plot tab from cached signal + metrics.
%
% Only the selected tab is drawn: a full refresh runs on every parameter edit
% in StimPlayer, and redrawing four sets of axes (the spectrogram especially)
% is several times more expensive than redrawing one. The tab group's
% SelectionChangedFcn calls back here, so a tab is always current by the time
% it becomes visible.
%
% Every level drawn here goes through obj.to_db_, which is dB SPL by way of
% stimgen.calibration.Engine.volts_to_spl when the record is shown as sound
% (obj.Scale.Acoustic) and dB re 1 otherwise, so one switch moves every axis
% between the two.
%
% Parameters:
%   M - metrics struct from stimgen.StimInspector.signal_metrics.  Pass
%       obj.Metrics to redraw without recomputing (used by the tab controls).

if ~obj.is_open()
    return
end

if nargin < 2 || ~isstruct(M) || ~isfield(M, 'Valid')
    M = stimgen.StimInspector.signal_metrics(obj.Signal_, obj.Fs_, obj.NHarmonics);
end

y  = obj.Signal_;
fs = obj.Fs_;

tg = obj.handles.TabGroup;
if isempty(tg.SelectedTab)
    return
end

switch tg.SelectedTab.Title
    case 'Waveform'
        plot_waveform_(obj, y, fs, M);
    case 'Spectrum'
        plot_spectrum_(obj, M);
    case 'Spectrogram'
        plot_spectrogram_(obj, y, fs, M);
    case 'Distortion'
        plot_harmonics_(obj, M);
    case 'Bands'
        plot_bands_(obj, y, fs, M);
    case 'Sound Level'
        plot_sound_level_(obj, y, fs, M);
end
end % update_plots_


% =========================================================================

function plot_waveform_(obj, y, fs, M)
% Time-domain waveform with its analytic envelope, plus the envelope in dB.
% As sound: pressure in pascals over the envelope in dB peSPL (the envelope
% is an amplitude, read as the rms of a sine with that peak), with the noise
% floor drawn across it when the capture recorded one.

axWave = obj.handles.AxWave;
axEnv  = obj.handles.AxEnvelope;
cla(axWave);
cla(axEnv);

acoustic = obj.Scale.Acoustic;
if acoustic
    ylabel(axWave, 'pressure (Pa)');
    ylabel(axEnv, stimgen.util.level_unit("peak"));
else
    ylabel(axWave, 'amplitude');
    ylabel(axEnv, 'dB');
end

if isempty(y) || ~M.Valid
    title(axWave, 'Time Domain');
    title(axEnv, 'Envelope (dB re peak)');
    return
end

t = (0:numel(y)-1) / fs * 1e3;  % ms, per the package-wide display convention

if acoustic
    % DC is not sound: the pressure trace, its envelope and its rms are all
    % taken without it, as every level in the metrics table is.
    k    = 1 / obj.Scale.MicSensitivity;
    yp   = (y - mean(y)) * k;
    env  = acoustic_envelope_(y - mean(y), numel(y)) * k;
    rmsY = sqrt(mean(yp .^ 2));
else
    yp   = y;
    env  = M.Envelope;
    rmsY = M.RMS;
end

[tp, ypp] = decimate_for_plot_(t, yp, obj.MaxPlotPoints);
line(axWave, tp, ypp, 'Color', [0.20 0.40 0.80]);
hold(axWave, 'on');

if ~isempty(env)
    [te, ye] = decimate_for_plot_(t, env, obj.MaxPlotPoints);
    line(axWave, te,  ye, 'Color', [0.85 0.33 0.10], 'LineWidth', 1);
    line(axWave, te, -ye, 'Color', [0.85 0.33 0.10], 'LineWidth', 1);
end

line(axWave, [t(1) t(end)], [ rmsY  rmsY], 'Color', [0.4 0.4 0.4], 'LineStyle', ':');
line(axWave, [t(1) t(end)], [-rmsY -rmsY], 'Color', [0.4 0.4 0.4], 'LineStyle', ':');
hold(axWave, 'off');

xlim(axWave, [t(1) max(t(end), t(1) + eps)]);
yl = max(abs(yp)) * 1.1;
if yl > 0
    ylim(axWave, [-yl yl]);
end

if acoustic
    S = obj.sound_levels_();
    z = S.Weightings == "Z";
    title(axWave, sprintf('Sound Pressure  (peak %.4g Pa = %.1f dB SPL, LZeq %.1f dB SPL, crest %.1f dB)', ...
        max(abs(yp)), S.Lpeak(z), S.Leq(z), S.Lpeak(z) - S.Leq(z)));
else
    title(axWave, sprintf('Time Domain  (peak %.4g, RMS %.4g, crest %.1f dB)', ...
        M.Peak, M.RMS, M.CrestFactorDb));
end

% --- Envelope in dB: makes the onset/offset ramp shape readable ---
if isempty(env)
    title(axEnv, 'Envelope (dB re peak) — not computed for this signal length');
    return
end

if acoustic
    % The envelope of a sinusoid is its amplitude, so dividing by sqrt(2)
    % puts the curve on the rms scale an SPL is defined on: a steady tone's
    % envelope reads its own level. Being a peak read as a sine's rms, it is
    % peak-equivalent SPL, and labelled so -- a transient's envelope reads
    % well above its rms level.
    envDb = obj.to_db_(env / sqrt(2) / k);
    [te, ye] = decimate_for_plot_(t, envDb, obj.MaxPlotPoints);
    line(axEnv, te, ye, 'Color', [0.85 0.33 0.10]);
    top = max(envDb(isfinite(envDb)));
    lo  = top - 80;

    N = obj.noise_levels_();
    if ~isempty(N)
        floorDb = N.Leq(N.Weightings == "Z");
        if isfinite(floorDb)
            line(axEnv, [t(1) t(end)], [floorDb floorDb], ...
                'Color', [0.45 0.45 0.45], 'LineStyle', '--');
            text(axEnv, t(end), floorDb, ' noise floor', ...
                'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom', ...
                'FontSize', 8, 'Color', [0.35 0.35 0.35]);
            lo = min(lo, floorDb - 10);
        end
    end
    xlim(axEnv, [t(1) max(t(end), t(1) + eps)]);
    if isfinite(top)
        ylim(axEnv, [lo, top + 5]);
    end
    title(axEnv, 'Envelope (dB peSPL: amplitude as a sine''s rms)');
    return
end

envDb = 20*log10(max(env, eps) / max(env));
[te, ye] = decimate_for_plot_(t, envDb, obj.MaxPlotPoints);
line(axEnv, te, ye, 'Color', [0.85 0.33 0.10]);
xlim(axEnv, [t(1) max(t(end), t(1) + eps)]);
ylim(axEnv, [-80 3]);
title(axEnv, 'Envelope (dB re peak)');
end


function plot_spectrum_(obj, M)
% Single-sided spectrum with optional harmonic markers and noise floor.
%
% Per-bin levels are the rms of a sinusoid centred on the bin -- right for a
% tone, and the scale the tone table is built on. For anything broadband the
% level in a bin depends on how wide the bin is, which is what the density
% view divides out: it is the one to compare two noise floors in, or a noise
% floor with a noise stimulus. The capture's noise floor is drawn on the same
% footing either way: per bin, it is the power one bin of THIS spectrum would
% hold, so the gap between the curves is a signal-to-noise ratio.

ax = obj.handles.AxSpectrum;
cla(ax);
legend(ax, 'off');

acoustic = obj.Scale.Acoustic;
density  = obj.handles.DensityCheck.Value;

if isempty(M.Freq) || ~M.Valid
    set(ax, 'XScale', 'linear');
    title(ax, 'Magnitude Spectrum');
    return
end

f   = M.Freq;
amp = 10 .^ (M.MagDb / 20);             % a sinusoid's amplitude, per bin

if acoustic
    curve = obj.to_db_(amp / sqrt(2));
    if density
        curve = curve - 10*log10(M.EnbwHz);
        yText = 'density (dB SPL/Hz)';
    else
        yText = 'level (dB SPL per bin)';
    end
elseif density
    curve = obj.to_db_(amp / sqrt(2)) - 10*log10(M.EnbwHz);
    yText = 'density (dB re 1/Hz, rms)';
else
    curve = M.MagDb;
    yText = 'magnitude (dB re full scale)';
end
ylabel(ax, yText);

useLog = obj.handles.LogFreqCheck.Value;

% The floor first, so the record is drawn over it.
hNoise = [];
if obj.handles.NoiseFloorCheck.Value && numel(obj.Noise_) >= 8
    [fn, pn] = noise_psd_(obj.Noise_, M.Fs);
    if density
        nc = obj.to_db_(sqrt(pn));
    elseif acoustic
        nc = obj.to_db_(sqrt(pn * M.EnbwHz));
    else
        nc = obj.to_db_(sqrt(2 * pn * M.EnbwHz));   % on MagDb's sine-amplitude scale
    end
    hNoise = line(ax, fn, nc, 'Color', [0.55 0.55 0.55]);
end

hold(ax, 'on');
hSig = line(ax, f, curve, 'Color', [0.20 0.40 0.80]);

if obj.handles.MarkHarmonicsCheck.Value && ~isempty(M.HarmonicHz)
    % Mark the harmonics thd() located, reading their level off the curve
    % drawn here so markers and trace always agree.
    hz = M.HarmonicHz(M.HarmonicHz > 0 & M.HarmonicHz <= f(end));
    if ~isempty(hz)
        db = interp1(f, curve, hz, 'linear', NaN);
        line(ax, hz, db, 'LineStyle', 'none', 'Marker', 'v', ...
            'MarkerSize', 7, 'MarkerFaceColor', [0.85 0.33 0.10], ...
            'MarkerEdgeColor', [0.4 0.15 0.05]);
        for k = 1:numel(hz)
            if isfinite(db(k))
                text(ax, hz(k), db(k) + 3, sprintf('H%d', k), ...
                    'HorizontalAlignment', 'center', 'FontSize', 8, ...
                    'Color', [0.4 0.15 0.05]);
            end
        end
    end
end
hold(ax, 'off');

if ~isempty(hNoise)
    legend(ax, [hSig hNoise], {'record', 'noise floor (before the stimulus)'}, ...
        'Location', 'northwest', 'AutoUpdate', 'off');
end

% A log axis cannot show DC; start at the first resolvable bin.
loF = f(2);
if useLog
    set(ax, 'XScale', 'log');
else
    set(ax, 'XScale', 'linear');
    loF = 0;
end
xlim(ax, [max(loF, 0) f(end)]);

topDb = max(curve(isfinite(curve)));
if isfinite(topDb)
    ylim(ax, [topDb - 120, topDb + 10]);
end

if acoustic
    f0Db = obj.to_db_(10 ^ (M.FundamentalDb / 20) / sqrt(2));
    if isfinite(M.ThdPercent)
        title(ax, sprintf('Level Spectrum  (F0 %.4g Hz at %.1f dB SPL, THD %.3f%%, SFDR %.1f dB)', ...
            M.FundamentalHz, f0Db, M.ThdPercent, M.SfdrDb));
    else
        title(ax, sprintf('Level Spectrum  (peak %.4g Hz at %.1f dB SPL)', M.FundamentalHz, f0Db));
    end
elseif isfinite(M.ThdPercent)
    title(ax, sprintf('Magnitude Spectrum  (F0 %.4g Hz, THD %.3f%%, SFDR %.1f dB)', ...
        M.FundamentalHz, M.ThdPercent, M.SfdrDb));
else
    title(ax, sprintf('Magnitude Spectrum  (peak %.4g Hz)', M.FundamentalHz));
end
end


function plot_spectrogram_(obj, y, fs, M)
% Power spectrogram at the FFT length chosen in the tab controls, per bin or
% as a density, in dB SPL when the record is shown as sound.

ax = obj.handles.AxSpectrogram;
cla(ax);

if isempty(y) || ~M.Valid
    title(ax, 'Spectrogram');
    return
end

nfft = obj.handles.SpecNfftDD.Value;
if numel(y) < nfft * 2
    nfft = 2^max(4, floor(log2(numel(y)/2)));
end
if numel(y) < nfft || nfft < 16
    title(ax, 'Spectrogram — signal too short');
    return
end

winFcn = str2func(obj.handles.SpecWindowDD.Value);
win    = winFcn(nfft);

density = obj.handles.SpecDensityCheck.Value;
if density
    kind = 'psd';
else
    kind = 'power';
end

try
    [~, freqVec, timeVec, ps] = spectrogram(y, win, round(nfft*0.75), nfft, fs, kind);
catch ME
    title(ax, 'Spectrogram — unavailable');
    stimgen.util.vprintf(2, 1, 'StimInspector: spectrogram failed: %s', ME.message);
    return
end

if obj.Scale.Acoustic
    % Power per bin (or per Hz) is a mean square, so its root is the rms the
    % level is defined on.
    psDb = obj.to_db_(sqrt(max(ps, realmin)));
    if density
        cbText = 'density (dB SPL/Hz)';
    else
        cbText = 'level (dB SPL)';
    end
else
    psDb = 10*log10(ps + eps);
    if density
        cbText = 'density (dB/Hz)';
    else
        cbText = 'power (dB)';
    end
end
tMs  = timeVec(:).' * 1e3;                   % time axis in ms
fHz  = freqVec(:).';

if obj.handles.SpecLogFreqCheck.Value
    % An image is not resampled by a non-linear axis transform: MATLAB maps
    % only its four corners, so on a log axis the spectrogram collapses into a
    % wedge. A flat-shaded surface is transformed per face and draws correctly.
    tEdges = bin_edges_(tMs);
    fEdges = bin_edges_(fHz);
    C      = psDb(2:end, :);                 % a log axis cannot show the DC bin,
    fEdges = fEdges(2:end);                  % whose lower edge is below 0 Hz too
    C(end+1, end+1) = 0;                     % flat shading ignores the last row/column
    surface(ax, tEdges, fEdges, zeros(size(C)), C, ...
        'FaceColor', 'flat', 'EdgeColor', 'none');
    set(ax, 'YScale', 'log', 'YDir', 'normal');
    ylim(ax, [fEdges(1), fs/2]);
    xlim(ax, [tEdges(1), tEdges(end)]);      % keep the plot tight in the axes
else
    imagesc(ax, tMs, fHz, psDb);
    axis(ax, 'xy');
    set(ax, 'YScale', 'linear');
    ylim(ax, [0, fs/2]);
    xlim(ax, [tMs(1), tMs(end)]);
end
xlabel(ax, 'time (ms)');
ylabel(ax, 'frequency (Hz)');

topDb = max(psDb(isfinite(psDb)));
if ~isempty(topDb) && isfinite(topDb)
    set(ax, 'CLim', [topDb - 90, topDb]);   % set() rather than clim(): R2021a
end

cb = colorbar(ax);
cb.Label.String = cbText;
d = obj.handles.SpecWindowDD;
winName = d.Items{strcmp(d.ItemsData, d.Value)};
title(ax, sprintf('Spectrogram  (%d-point FFT, %s window, %.1f Hz resolution)', nfft, winName, fs/nfft));
end


function plot_harmonics_(obj, M)
% Harmonic levels relative to the fundamental, as a bar chart and a table.
% The table also gives each harmonic's own level -- in dB SPL for a record
% shown as sound, which is how a distortion product is judged against
% threshold rather than against its own fundamental.

ax = obj.handles.AxHarmonics;
tbl = obj.handles.HarmonicsTable;
cla(ax);

if obj.Scale.Acoustic
    levelName = 'Level (dB SPL)';
else
    levelName = 'Level (dB re 1)';
end
tbl.ColumnName = {'Harmonic', 'Frequency (Hz)', 'Level (dB re F0)', 'Amplitude (%)', levelName};

if isempty(M.HarmonicDb) || numel(M.HarmonicDb) < 2
    tbl.Data = cell(0, 5);
    title(ax, 'Harmonic Levels — no fundamental resolved');
    return
end

rel = M.HarmonicDb - M.HarmonicDb(1);   % dB re fundamental; reference cancels
n   = numel(rel);

% thd() reports each harmonic's power (a mean square) in dB; its root is the
% rms a level is taken from.
if obj.Scale.Acoustic
    absDb = obj.to_db_(sqrt(10 .^ (M.HarmonicDb / 10)));
else
    absDb = M.HarmonicDb;
end

% Bars rise from a fixed floor rather than hanging down from 0 dB, so a clean
% stimulus reads as short bars and a distorted one as tall bars.
floorDb = -140;
b = bar(ax, 1:n, max(rel, floorDb), 'FaceColor', [0.20 0.40 0.80]);
b.BaseValue = floorDb;
xlim(ax, [0.4 n + 0.6]);
xticks(ax, 1:n);
xticklabels(ax, arrayfun(@(k) sprintf('H%d', k), 1:n, 'uni', false));
ylim(ax, [floorDb, 5]);
xlabel(ax, 'harmonic');
ylabel(ax, 'dB re fundamental');
grid(ax, 'on');

if isfinite(M.ThdPercent)
    title(ax, sprintf('Harmonic Levels  (THD %.4f%% / %.1f dB over %d harmonics)', ...
        M.ThdPercent, M.ThdDb, n - 1));
else
    title(ax, 'Harmonic Levels');
end

rows = cell(n, 5);
for k = 1:n
    rows{k, 1} = sprintf('H%d%s', k, tern_(k == 1, ' (fundamental)', ''));
    rows{k, 2} = sprintf('%.5g', M.HarmonicHz(k));
    rows{k, 3} = sprintf('%.2f', rel(k));
    rows{k, 4} = sprintf('%.4f', 100 * 10^(rel(k)/20));
    rows{k, 5} = sprintf('%.2f', absDb(k));
end
tbl.Data = rows;
end


function plot_bands_(obj, y, fs, M)
% Fractional-octave band levels, weighted by the curve at each band centre,
% with the capture's noise floor in the same bands and the SNR per band.
%
% Integrated from a Hann periodogram of the whole record through
% stimgen.util.band_levels, the same band arithmetic the calibration's
% background analysis uses. A band is only reported once the record resolves
% it -- its lower edge at least five resolution cells up -- so a short tone
% pip shows fewer low bands rather than one-bin guesses dressed as bands.

ax  = obj.handles.AxBands;
tbl = obj.handles.BandsTable;
cla(ax);
legend(ax, 'off');

acoustic = obj.Scale.Acoustic;
frac = double(obj.handles.BandFractionDD.Value);
wt   = string(obj.handles.BandWeightingDD.Value);
[fracText, wtText] = band_names_(frac, wt);

if acoustic
    unit = 'dB SPL';
else
    unit = 'dB re 1';
end
ylabel(ax, sprintf('band level (%s%s)', unit, weight_suffix_(wt)));
tbl.ColumnName = {'Centre (Hz)', ['Level (' unit ')'], ['Noise floor (' unit ')'], 'SNR (dB)'};

if isempty(y) || ~M.Valid || numel(y) < 8
    title(ax, 'Band Levels');
    tbl.Data = cell(0, 4);
    return
end

B = band_table_(obj, y, fs, frac, wt);
n = numel(B.frequency);
if n == 0
    title(ax, 'Band Levels — the record is too short to resolve any band');
    tbl.Data = cell(0, 4);
    return
end

nLvl = nan(1, n);
showNoise = obj.handles.BandNoiseCheck.Value && numel(obj.Noise_) >= 8;
if showNoise
    NB = band_table_(obj, obj.Noise_, fs, frac, wt);
    if ~isempty(NB.frequency)
        [tf, loc] = ismembertol(B.frequency, NB.frequency, 1e-9);
        nLvl(tf) = NB.level(loc(tf));
    end
end

allDb   = [B.level, nLvl];
allDb   = allDb(isfinite(allDb));
floorDb = 10 * floor((min(allDb) - 10) / 10);
topDb   = max(B.level(isfinite(B.level)));

x = 1:n;
b = bar(ax, x, B.level, 'FaceColor', [0.20 0.40 0.80], 'EdgeColor', 'none');
b.BaseValue = floorDb;
hold(ax, 'on');
handlesLeg = b;
namesLeg   = {'record'};
if showNoise && any(isfinite(nLvl))
    hn = line(ax, x, nLvl, 'Color', [0.45 0.45 0.45], 'LineWidth', 1.2, ...
        'Marker', 'o', 'MarkerSize', 4, 'MarkerFaceColor', [0.45 0.45 0.45]);
    handlesLeg = [handlesLeg, hn];   % concatenated: a Bar array cannot hold a Line
    namesLeg{end+1} = 'noise floor';
end
hold(ax, 'off');

labels = arrayfun(@(fc) band_label_(fc, frac), B.frequency, 'uni', false);
step = max(1, ceil(n / 16));
xticks(ax, x(1:step:end));
xticklabels(ax, labels(1:step:end));
xtickangle(ax, 45);
xlim(ax, [0.4, n + 0.6]);
if isfinite(topDb) && isfinite(floorDb)
    ylim(ax, [floorDb, topDb + 5]);
end
if numel(handlesLeg) > 1
    legend(ax, handlesLeg, namesLeg, 'Location', 'northeast', 'AutoUpdate', 'off');
end

total = 10 * log10(sum(10 .^ (B.level(isfinite(B.level)) / 10)));
title(ax, sprintf('%s Band Levels, %s  (sum of bands %.1f %s)', ...
    fracText, wtText, total, unit));

rows = cell(n, 4);
for k = 1:n
    rows{k, 1} = labels{k};
    rows{k, 2} = sprintf('%.2f', B.level(k));
    if isfinite(nLvl(k))
        rows{k, 3} = sprintf('%.2f', nLvl(k));
        rows{k, 4} = sprintf('%.2f', B.level(k) - nLvl(k));
    else
        rows{k, 3} = '';
        rows{k, 4} = '';
    end
end
tbl.Data = rows;
end


function plot_sound_level_(obj, y, fs, M)
% What a sound level meter would read. The time-weighted level against time
% for the chosen weighting, its Leq and the noise floor drawn across it, over
% a table of every readout for Z, A and C (stimgen.util.sound_levels).

ax   = obj.handles.AxLevelHistory;
tbl  = obj.handles.LevelTable;
note = obj.handles.LevelNote;
cla(ax);
legend(ax, 'off');

acoustic = obj.Scale.Acoustic;
if acoustic
    unit = 'dB SPL';
else
    unit = 'dB re 1';
end
ylabel(ax, sprintf('level (%s)', unit));

if isempty(y) || ~M.Valid
    title(ax, 'Time-Weighted Level');
    tbl.Data = cell(0, 4);
    note.Text = '';
    return
end

wt = string(obj.handles.HistoryWeightingDD.Value);
tw = string(obj.handles.TimeWeightingDD.Value);

S = obj.sound_levels_();
N = obj.noise_levels_();
H = stimgen.util.sound_levels(y, fs, obj.display_sensitivity_(), ...
    Weightings = wt, History = wt, TimeWeighting = tw);

if isempty(H.History)
    title(ax, 'Time-Weighted Level — no signal');
    tbl.Data = cell(0, 4);
    note.Text = '';
    return
end

t = H.History.t_s * 1e3;
L = H.History.level_db;
L(~isfinite(L)) = NaN;
if ~any(isfinite(L))
    title(ax, 'Time-Weighted Level — no signal');
    tbl.Data = cell(0, 4);
    note.Text = '';
    return
end
[tp, Lp] = decimate_for_plot_(t, L, obj.MaxPlotPoints);
line(ax, tp, Lp, 'Color', [0.20 0.40 0.80], 'LineWidth', 1);
hold(ax, 'on');

wi  = S.Weightings == wt;
leq = S.Leq(wi);
line(ax, [t(1) t(end)], [leq leq], 'Color', [0.85 0.33 0.10], 'LineStyle', '--');
text(ax, t(1), leq, sprintf(' L_{%seq} %.1f', wt, leq), 'VerticalAlignment', 'bottom', ...
    'FontSize', 8, 'Color', [0.60 0.22 0.05]);

lo = max(Lp(isfinite(Lp))) - 60;
if ~isempty(N)
    floorDb = N.Leq(N.Weightings == wt);
    if isfinite(floorDb)
        line(ax, [t(1) t(end)], [floorDb floorDb], 'Color', [0.45 0.45 0.45], 'LineStyle', ':');
        text(ax, t(end), floorDb, sprintf('noise floor %.1f ', floorDb), ...
            'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom', ...
            'FontSize', 8, 'Color', [0.35 0.35 0.35]);
        lo = min(lo, floorDb - 10);
    end
end
hold(ax, 'off');

top = max([Lp(isfinite(Lp)), leq]);
if isfinite(top) && isfinite(lo)
    ylim(ax, [lo, top + 5]);
end
xlim(ax, [t(1) max(t(end), t(1) + eps)]);

twName = tern_(tw == "S", 'Slow', 'Fast');
title(ax, sprintf('L_{%s%s}(t), %s  (L_{%s%s,max} %.1f, L_{%seq} %.1f %s)', ...
    wt, tw, twName, wt, tw, max(Lp), wt, leq, unit));

% --- The readout table: rows are quantities, columns are weightings -------
cols = ["Z", "A", "C"];
pick = @(v) arrayfun(@(w) fmt_(v(S.Weightings == w)), cols, 'uni', false);
rows = [ ...
    [{'Leq (equivalent)'},        pick(S.Leq)]; ...
    [{'Lpeak (peak)'},            pick(S.Lpeak)]; ...
    [{'LFmax (Fast, 125 ms)'},    pick(S.LFmax)]; ...
    [{'LSmax (Slow, 1 s)'},       pick(S.LSmax)]; ...
    [{'LE (exposure re 1 s)'},    pick(S.LE)]];
if ~isempty(N)
    nl = @(w) N.Leq(N.Weightings == w);
    rows = [rows; ...
        [{'Noise floor Leq'},     arrayfun(@(w) fmt_(nl(w)), cols, 'uni', false)]; ...
        [{'SNR (Leq - floor)'},   arrayfun(@(w) fmt_(S.Leq(S.Weightings == w) - nl(w)), cols, 'uni', false)]];
end
rows = [rows; ...
    {'peSPL (sine of equal peak)',  fmt_(S.peSPL),  '', ''}; ...
    {'ppeSPL (sine of equal p-p)',  fmt_(S.ppeSPL), '', ''}];
tbl.Data = rows;

durMs = numel(y) / fs * 1e3;
if acoustic
    lead = sprintf('dB re 20 µPa through %.4g mV/Pa.', obj.Scale.MicSensitivity * 1e3);
else
    lead = 'dB re 1 — no microphone scale, so these are signal levels, not sound levels.';
end
note.Text = sprintf(['%s  Z is unweighted up to Nyquist (%.4g kHz).  This record is %.0f ms; ' ...
    'Fast/Slow read low until it is several time constants long.'], lead, fs / 2e3, durMs);
end


% =========================================================================

function env = acoustic_envelope_(y, n)
% Analytic envelope of a record, skipped for very long ones exactly as
% signal_metrics skips it (an FFT pair over the whole record).
env = [];
if n <= 2^22
    try
        env = abs(hilbert(y));
    catch
        env = [];
    end
end
end


function [f, pxx] = noise_psd_(x, fs)
% One-sided PSD (units^2/Hz) of a noise record, Hann-windowed like the
% spectrum it is drawn under, as rows.
x = x(:) - mean(x);
n = numel(x);
nfft = max(2^nextpow2(n), 1024);
[pxx, f] = periodogram(x, hann(n), nfft, fs, 'psd');
pxx = pxx(:).';
f   = f(:).';
end


function B = band_table_(obj, x, fs, frac, wt)
% Weighted band levels of one record, on the scale on screen.
x = x(:) - mean(x);
n = numel(x);
nfft = max(2^nextpow2(n), 1024);
[pxx, f] = periodogram(x, hann(n), nfft, fs, 'psd');
fMin = max(5 * fs / n, 10);
b = stimgen.util.band_levels(pxx, f, f(2) - f(1), frac, fMin, fs / 2);
lvl = obj.to_db_(sqrt(max(b.power, realmin))) + stimgen.util.weighting_db(b.frequency, wt);
B = struct('frequency', b.frequency, 'level', lvl, 'edges', b.edges);
end


function [fracText, wtText] = band_names_(frac, wt)
% Words for a band set and a weighting, for titles.
switch frac
    case 1,     fracText = 'Octave';
    otherwise,  fracText = sprintf('1/%d-Octave', frac);
end
if wt == "Z"
    wtText = 'unweighted';
else
    wtText = sprintf('%s-weighted', wt);
end
end


function s = weight_suffix_(wt)
% ", A-weighted" or nothing, for an axis label.
if wt == "Z"
    s = '';
else
    s = sprintf(', %s-weighted', wt);
end
end


function s = band_label_(fc, frac)
% A band centre as it is conventionally written. Octave and third-octave
% centres snap to the IEC nominal values (1k, 1.25k, 3.15k ...), which is
% what their exact base-ten values are there to stand for; finer bands have
% no nominal series and are written to three figures.
if frac == 1 || frac == 3
    r = [1 1.25 1.6 2 2.5 3.15 4 5 6.3 8 10];
    e = floor(log10(fc));
    [~, i] = min(abs(log(r) - log(fc / 10^e)));
    v = r(i) * 10^e;
else
    v = str2double(sprintf('%.3g', fc));
end
if v >= 1000
    s = sprintf('%gk', v / 1000);
else
    s = sprintf('%g', v);
end
end


function s = fmt_(v)
% A level for the readout table: two decimals, blank when there is none.
if isempty(v) || ~isscalar(v) || ~isfinite(v)
    s = '';
else
    s = sprintf('%.2f', v);
end
end


function [xd, yd] = decimate_for_plot_(x, y, maxPoints)
% [xd, yd] = decimate_for_plot_(x, y, maxPoints)
% Reduce a dense trace to at most ~maxPoints while preserving its extremes.
% Each retained block contributes its min and its max, so a decimated
% waveform still shows its true peak amplitude.

n = numel(y);
if n <= maxPoints
    xd = x;
    yd = y;
    return
end

blk = ceil(n / max(1, floor(maxPoints/2)));
m   = floor(n/blk) * blk;

Y  = reshape(y(1:m), blk, []);
xc = x(1:blk:m);
lo = min(Y, [], 1);
hi = max(Y, [], 1);

xd = reshape([xc; xc], 1, []);
yd = reshape([lo; hi], 1, []);

if m < n
    xd = [xd x(m+1:n)];
    yd = [yd y(m+1:n)];
end
end


function e = bin_edges_(c)
% e = bin_edges_(c)
% Cell boundaries around the bin centres c, as a 1-by-(numel(c)+1) row. Used to
% place a spectrogram surface, whose faces span edges rather than centres.

c = c(:).';
if isscalar(c)
    e = [c - 0.5, c + 0.5];
    return
end

d = diff(c);
e = [c(1) - d(1)/2, c(1:end-1) + d/2, c(end) + d(end)/2];
end


function out = tern_(cond, a, b)
% tern_(cond, a, b) - Inline conditional value.
if cond
    out = a;
else
    out = b;
end
end
