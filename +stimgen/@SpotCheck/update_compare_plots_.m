function update_compare_plots_(obj)
% update_compare_plots_(obj)
% Redraw the two plots that are about the PAIR of waveforms.
%
% Everything about either signal on its own -- envelope, spectrogram, harmonic
% breakdown, the metrics table -- belongs to stimgen.StimInspector, and the
% toolbar opens one on each. What an inspector cannot show is the two together,
% which is exactly the comparison a spot check exists to make:
%
%   top     stimulus and recording overlaid on one time base. Both are
%           normalized to their own peak, because one is drive volts and the
%           other is microphone volts and their absolute scales have no
%           relationship. What this shows is SHAPE: whether the envelope
%           survived, whether the gate is still where it was, whether the
%           record was cut in the right place. A recording offset from the
%           stimulus here means the delay search failed, which is the failure
%           mode most likely to invalidate everything else on screen.
%
%   bottom  the two magnitude spectra, each in dB relative to its own peak,
%           so the same normalization argument applies. What this shows is
%           what the rig did to the spectrum: rolloff, resonances, and any
%           harmonic the speaker added that the stimulus did not have.

if ~obj.is_open()
    return
end

axStim = obj.handles.AxStim;
axRec  = obj.handles.AxRec;
axSpec = obj.handles.AxSpectrum;

cla(axStim);
cla(axRec);
cla(axSpec);

if isempty(obj.Capture)
    title(axStim, 'Stimulus');
    title(axRec,  'Recording');
    title(axSpec, 'Spectra');
    return
end

c  = obj.Capture;
fs = c.fs;
x  = c.excitation;
y  = c.response;

stimColor = [0.20 0.40 0.80];
recColor  = [0.85 0.33 0.10];

% ---- Time domain --------------------------------------------------------
t = (0:numel(x)-1) / fs * 1e3;   % ms, the package-wide display unit

draw_wave_(axStim, t, normalize_(x), stimColor, obj.MaxPlotPoints);
draw_wave_(axRec,  t, normalize_(y), recColor,  obj.MaxPlotPoints);

title(axStim, sprintf('Stimulus  (%.1f ms, peak %.4g)', t(end), max(abs(x))));
title(axRec,  sprintf('Recording  (peak %.4g V, %.2f ms conduction delay removed)', ...
    max(abs(y)), c.delay_s * 1e3));

% One time axis for the pair: panning or zooming either follows the other, so
% a feature can be tracked between them instead of being hunted for twice.
try
    linkaxes([axStim, axRec], 'x');
catch
    % Linking is a convenience; a failure must not cost the plots.
end

% ---- Spectra ------------------------------------------------------------
[f, xAbs] = spectrum_db_(x, fs);
[~, yAbs] = spectrum_db_(y, fs);

if isempty(f)
    title(axSpec, 'Spectra — signal too short');
    return
end

recRef = max(yAbs);     % what the recording trace is shifted by

% Recording first, stimulus over it. The stimulus is the reference the eye is
% comparing against, and a clean synthetic spectrum is the narrower of the two
% -- underneath, it vanishes wherever the two agree, which is most of the axis.
hold(axSpec, 'on');
line(axSpec, f, yAbs - recRef, 'Color', recColor, 'DisplayName', 'recording');
line(axSpec, f, xAbs - max(xAbs), 'Color', stimColor, 'DisplayName', 'stimulus');

% The noise floor the recording sat on, measured over the leading silence of
% this same record. Drawn because a spectral difference between the two traces
% is only real above it -- below, both traces are reading the room. Shifted by
% the RECORDING's reference, not its own, so it lands where it actually sits
% under that trace instead of being normalized up to fill the axis.
if ~isempty(c.noise.record) && numel(c.noise.record) >= 16
    [fn, nAbs] = spectrum_db_(c.noise.record, fs);
    if ~isempty(fn)
        line(axSpec, fn, nAbs - recRef, 'Color', [0.55 0.55 0.55], ...
            'LineStyle', ':', 'DisplayName', 'noise floor');
    end
end
hold(axSpec, 'off');

set(axSpec, 'XScale', 'log');
xlim(axSpec, [max(f(2), 10) fs/2]);
ylim(axSpec, [-100 5]);
legend(axSpec, 'Location', 'southwest', 'Box', 'off');
title(axSpec, 'Spectra (each dB re its own peak)');
end % update_compare_plots_


% =========================================================================

function draw_wave_(ax, t, y, color, maxPoints)
% draw_wave_(ax, t, y, color, maxPoints)
% One normalized waveform on its own axes, thinned for display.
%
% The envelope is drawn over the trace as well. For a stimulus of any length
% the raw waveform decimates into a solid band and its shape is carried
% entirely by the outline, so drawing that outline explicitly is what makes
% gating visible -- and a missing or truncated ramp is one of the things a
% spot check is looking for.

[td, yd] = decimate_for_plot_(t, y, maxPoints);
line(ax, td, yd, 'Color', color);

env = envelope_(y);
if ~isempty(env)
    [te, ye] = decimate_for_plot_(t, env, maxPoints);
    line(ax, te,  ye, 'Color', [0.15 0.15 0.15], 'LineWidth', 1);
    line(ax, te, -ye, 'Color', [0.15 0.15 0.15], 'LineWidth', 1);
end

if numel(t) > 1
    xlim(ax, [t(1) t(end)]);
end
ylim(ax, [-1.15 1.15]);
end


function env = envelope_(y)
% env = envelope_(y)
% Analytic-signal envelope, normalized alongside the trace it describes.
% Skipped for a very long record rather than stalling the window on an FFT
% pair, the same threshold stimgen.StimInspector.signal_metrics uses.
env = [];
if numel(y) > 2^22
    return
end
try
    env = abs(hilbert(y));
    p = max(env);
    if p > 0
        env = env ./ max(p, max(abs(y)));
    end
catch
    env = [];
end
end


function y = normalize_(y)
% Scale to unit peak so two signals on unrelated absolute scales can share an
% axis. A silent record is left alone rather than divided by zero.
p = max(abs(y));
if p > 0
    y = y ./ p;
end
end


function [f, magDb] = spectrum_db_(y, fs)
% [f, magDb] = spectrum_db_(y, fs)
% Single-sided magnitude spectrum in ABSOLUTE dB (re an amplitude of 1.0),
% Hann-windowed and corrected for the window's coherent gain so a full-scale
% sinusoid reads 0 dB -- the same convention
% stimgen.StimInspector.signal_metrics uses, so a trace drawn here and the
% inspector's spectrum tab agree.
%
% Absolute rather than peak-normalized because the caller decides what each
% trace is referenced to: two signals on unrelated scales each get their own
% reference, while the noise floor has to borrow the recording's.

f     = [];
magDb = [];

n = numel(y);
if n < 16
    return
end

w    = hann(n).';
nfft = 2^nextpow2(max(n, 1024));
Y    = fft(y .* w, nfft);
half = floor(nfft/2) + 1;

mag    = abs(Y(1:half)) * (2 / sum(w));
mag(1) = mag(1) / 2;
if mod(nfft, 2) == 0
    mag(half) = mag(half) / 2;
end

f     = (0:half-1) * (fs / nfft);
magDb = 20 * log10(max(mag, eps));
end


function [xd, yd] = decimate_for_plot_(x, y, maxPoints)
% Reduce a dense trace to about maxPoints while keeping its extremes: each
% retained block contributes its min and its max, so a decimated waveform still
% shows its true peak. Same approach as stimgen.StimInspector's waveform tab.

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
