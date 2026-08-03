function update_plots_(obj, M)
% update_plots_(obj, M) - Redraw the visible plot tab from cached signal + metrics.
%
% Only the selected tab is drawn: a full refresh runs on every parameter edit
% in StimPlayer, and redrawing four sets of axes (the spectrogram especially)
% is several times more expensive than redrawing one. The tab group's
% SelectionChangedFcn calls back here, so a tab is always current by the time
% it becomes visible.
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
end
end % update_plots_


% =========================================================================

function plot_waveform_(obj, y, fs, M)
% Time-domain waveform with its analytic envelope, plus the envelope in dB.

axWave = obj.handles.AxWave;
axEnv  = obj.handles.AxEnvelope;
cla(axWave);
cla(axEnv);

if isempty(y) || ~M.Valid
    title(axWave, 'Time Domain');
    title(axEnv, 'Envelope (dB re peak)');
    return
end

t = (0:numel(y)-1) / fs * 1e3;  % ms, per the package-wide display convention

[tp, yp] = decimate_for_plot_(t, y, obj.MaxPlotPoints);
line(axWave, tp, yp, 'Color', [0.20 0.40 0.80]);
hold(axWave, 'on');

if ~isempty(M.Envelope)
    [te, ye] = decimate_for_plot_(t, M.Envelope, obj.MaxPlotPoints);
    line(axWave, te,  ye, 'Color', [0.85 0.33 0.10], 'LineWidth', 1);
    line(axWave, te, -ye, 'Color', [0.85 0.33 0.10], 'LineWidth', 1);
end

line(axWave, [t(1) t(end)], [ M.RMS  M.RMS], 'Color', [0.4 0.4 0.4], 'LineStyle', ':');
line(axWave, [t(1) t(end)], [-M.RMS -M.RMS], 'Color', [0.4 0.4 0.4], 'LineStyle', ':');
hold(axWave, 'off');

xlim(axWave, [t(1) max(t(end), t(1) + eps)]);
yl = max(abs(y)) * 1.1;
if yl > 0
    ylim(axWave, [-yl yl]);
end
title(axWave, sprintf('Time Domain  (peak %.4g, RMS %.4g, crest %.1f dB)', ...
    M.Peak, M.RMS, M.CrestFactorDb));

% --- Envelope in dB: makes the onset/offset ramp shape readable ---
if isempty(M.Envelope)
    title(axEnv, 'Envelope (dB re peak) — not computed for this signal length');
    return
end

envDb = 20*log10(max(M.Envelope, eps) / max(M.Envelope));
[te, ye] = decimate_for_plot_(t, envDb, obj.MaxPlotPoints);
line(axEnv, te, ye, 'Color', [0.85 0.33 0.10]);
xlim(axEnv, [t(1) max(t(end), t(1) + eps)]);
ylim(axEnv, [-80 3]);
title(axEnv, 'Envelope (dB re peak)');
end


function plot_spectrum_(obj, M)
% Single-sided magnitude spectrum with optional harmonic markers.

ax = obj.handles.AxSpectrum;
cla(ax);

if isempty(M.Freq) || ~M.Valid
    set(ax, 'XScale', 'linear');
    title(ax, 'Magnitude Spectrum');
    return
end

f    = M.Freq;
magDb = M.MagDb;

useLog = obj.handles.LogFreqCheck.Value;

line(ax, f, magDb, 'Color', [0.20 0.40 0.80]);
hold(ax, 'on');

if obj.handles.MarkHarmonicsCheck.Value && ~isempty(M.HarmonicHz)
    % Mark the harmonics thd() located, reading their level off the curve
    % drawn here so markers and trace always agree.
    hz = M.HarmonicHz(M.HarmonicHz > 0 & M.HarmonicHz <= f(end));
    if ~isempty(hz)
        db = interp1(f, magDb, hz, 'linear', NaN);
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

% A log axis cannot show DC; start at the first resolvable bin.
loF = f(2);
if useLog
    set(ax, 'XScale', 'log');
else
    set(ax, 'XScale', 'linear');
    loF = 0;
end
xlim(ax, [max(loF, 0) f(end)]);

topDb = max(magDb);
if isfinite(topDb)
    ylim(ax, [topDb - 120, topDb + 10]);
end

if isfinite(M.ThdPercent)
    title(ax, sprintf('Magnitude Spectrum  (F0 %.4g Hz, THD %.3f%%, SFDR %.1f dB)', ...
        M.FundamentalHz, M.ThdPercent, M.SfdrDb));
else
    title(ax, sprintf('Magnitude Spectrum  (peak %.4g Hz)', M.FundamentalHz));
end
end


function plot_spectrogram_(obj, y, fs, M)
% Power spectrogram at the FFT length chosen in the tab controls.

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

try
    [~, freqVec, timeVec, ps] = spectrogram(y, win, round(nfft*0.75), nfft, fs, 'power');
catch ME
    title(ax, 'Spectrogram — unavailable');
    stimgen.util.vprintf(2, 1, 'StimInspector: spectrogram failed: %s', ME.message);
    return
end

psDb = 10*log10(ps + eps);
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

topDb = max(psDb(:));
if isfinite(topDb)
    set(ax, 'CLim', [topDb - 90, topDb]);   % set() rather than clim(): R2021a
end

cb = colorbar(ax);
cb.Label.String = 'power (dB)';
d = obj.handles.SpecWindowDD;
winName = d.Items{strcmp(d.ItemsData, d.Value)};
title(ax, sprintf('Spectrogram  (%d-point FFT, %s window, %.1f Hz resolution)', nfft, winName, fs/nfft));
end


function plot_harmonics_(obj, M)
% Harmonic levels relative to the fundamental, as a bar chart and a table.

ax = obj.handles.AxHarmonics;
tbl = obj.handles.HarmonicsTable;
cla(ax);

if isempty(M.HarmonicDb) || numel(M.HarmonicDb) < 2
    tbl.Data = cell(0, 4);
    title(ax, 'Harmonic Levels — no fundamental resolved');
    return
end

rel = M.HarmonicDb - M.HarmonicDb(1);   % dB re fundamental; reference cancels
n   = numel(rel);

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

rows = cell(n, 4);
for k = 1:n
    rows{k, 1} = sprintf('H%d%s', k, tern_(k == 1, ' (fundamental)', ''));
    rows{k, 2} = sprintf('%.5g', M.HarmonicHz(k));
    rows{k, 3} = sprintf('%.2f', rel(k));
    rows{k, 4} = sprintf('%.4f', 100 * 10^(rel(k)/20));
end
tbl.Data = rows;
end


% =========================================================================

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
