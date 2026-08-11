function make_wiki_figures(outDir)
% make_wiki_figures()
% make_wiki_figures(outDir)
% Render the waveform and spectrogram figures used by the wiki's
% Stimulus-Types page, one pair per stimulus class.
%
% Every figure is generated from the real class, so re-running this after a
% change to a stimulus regenerates the documentation to match it.
%
% Parameters:
%   outDir - Folder to write the PNGs into. Default: a stimgen_wiki_figures
%            folder under tempdir. To refresh the published page, point this
%            at the images folder of a checkout of the wiki repository
%            (https://github.com/dstolz/stimgen.wiki.git), then commit there:
%
%              make_wiki_figures('C:\src\stimgen.wiki\images')
%
% The file names are stim_<Class>_waveform.png and stim_<Class>_spectrogram.png
% and are referenced by those names from Stimulus-Types.md, so renaming one
% breaks the page.
%
% Only the spectrotemporally complex classes get a spectrogram; a pure Tone
% has nothing to show in one.
%
% See also stimgen.StimType/plot, stimgen.StimType/plot_spectrogram.

if nargin < 1 || isempty(outDir)
    outDir = fullfile(tempdir, 'stimgen_wiki_figures');
end
if ~isfolder(outDir), mkdir(outDir); end

% The package root is the parent of this documentation folder.
addpath(fileparts(fileparts(mfilename('fullpath'))));

fprintf('writing to %s\n', outDir);

%% ---------------------------------------------------------------- Tone
t = stimgen.Tone;
t.Frequency      = 1000;
t.Duration       = 0.05;
t.WindowDuration = 0.005;
t.update_signal;
wave_fig(t, fullfile(outDir,'stim_Tone_waveform.png'), ...
    'Tone — 1 kHz, 50 ms, 5 ms cos^2 gate');

%% --------------------------------------------------------------- Noise
% FilterOrder matters: the default 40 taps is far too short to shape a band
% at Fs ~ 98 kHz, so use an order that actually realizes the cutoffs.
n = stimgen.Noise;
n.HighPass    = 2000;
n.LowPass     = 8000;
n.FilterOrder = 512;
n.Duration    = 0.1;
n.update_signal;
wave_fig(n, fullfile(outDir,'stim_Noise_waveform.png'), ...
    'Noise — 2–8 kHz band, 100 ms, FIR order 512');
spec_fig(n, fullfile(outDir,'stim_Noise_spectrogram.png'), ...
    'Noise — 2–8 kHz band: flat passband between the FIR cutoffs', 512, [0 20]);

%% ------------------------------------------------------------- AMnoise
a = stimgen.AMnoise;
a.HighPass    = 2000;
a.LowPass     = 16000;
a.FilterOrder = 512;
a.AMRate      = 20;
a.AMDepth     = 1;
a.Duration    = 0.5;
a.update_signal;
wave_fig(a, fullfile(outDir,'stim_AMnoise_waveform.png'), ...
    'AMnoise — 2–16 kHz noise, 20 Hz modulation, depth 1');
spec_fig(a, fullfile(outDir,'stim_AMnoise_spectrogram.png'), ...
    'AMnoise — modulation appears as broadband intensity fluctuation at 20 Hz', 512, [0 20]);

%% ------------------------------------------------------ AttackModNoise
% Two panels: ramped (Z<0) and damped (Z>0), which is the defining contrast.
% Z = +/-1 is used rather than a milder value because the envelope is
% t^(1-|z|)*(1-t), which only becomes a clean one-sided ramp at |z| = 1.
r = stimgen.AttackModNoise;
r.HighPass = 2000; r.LowPass = 16000; r.FilterOrder = 512;
r.AMRate = 20; r.Duration = 0.5; r.Z = -1;
r.update_signal;
d = stimgen.AttackModNoise;
d.HighPass = 2000; d.LowPass = 16000; d.FilterOrder = 512;
d.AMRate = 20; d.Duration = 0.5; d.Z = 1;
d.update_signal;

f = new_fig(1000, 460);
tl = tiledlayout(f, 2, 1, 'TileSpacing','compact', 'Padding','compact');
ax1 = nexttile(tl); draw_wave(ax1, r); title(ax1, 'Z = -1  (ramped: gradual attack, abrupt offset)');
ax2 = nexttile(tl); draw_wave(ax2, d); title(ax2, 'Z = +1  (damped: abrupt onset, gradual decay)');
xlabel(ax1, '');
title(tl, 'AttackModNoise — 2–16 kHz noise, 20 Hz modulation rate', ...
    'FontWeight','bold','FontSize',12);
save_fig(f, fullfile(outDir,'stim_AttackModNoise_waveform.png'));
spec_fig(d, fullfile(outDir,'stim_AttackModNoise_spectrogram.png'), ...
    'AttackModNoise (Z = +1, damped) — an abrupt broadband onset every 50 ms, then decay', ...
    512, [0 20]);

%% -------------------------------------------------------------- FMtone
m = stimgen.FMtone;
m.CarrierFrequency    = 4000;
m.ModulationFrequency = 10;
m.ModulationDepth     = 300;    % realized deviation, in Hz, about the carrier
m.Duration            = 0.5;
m.update_signal;
wave_fig(m, fullfile(outDir,'stim_FMtone_waveform.png'), ...
    'FMtone — 4 kHz carrier, 10 Hz modulation, 300 Hz depth');
spec_fig(m, fullfile(outDir,'stim_FMtone_spectrogram.png'), ...
    'FMtone — instantaneous frequency sweeps sinusoidally about the 4 kHz carrier', ...
    1024, [0 8]);

%% ----------------------------------------------------------- ClickTrain
c = stimgen.ClickTrain;
c.Rate          = 50;
c.ClickDuration = 100e-6;
c.Duration      = 0.2;
c.update_signal;

% A 100 us click is ~10 samples wide, so the train alone shows only hairlines;
% the second panel zooms in on the first click to show the actual pulse.
f = new_fig(1000, 460);
tl = tiledlayout(f, 2, 1, 'TileSpacing','compact', 'Padding','compact');
ax1 = nexttile(tl); draw_wave(ax1, c); title(ax1, 'the full 200 ms train');
ax2 = nexttile(tl); draw_wave(ax2, c); title(ax2, 'first click, zoomed');
ax2.XLim = [-0.1 0.5];
xlabel(ax1, '');
title(tl, 'ClickTrain — 50 Hz, 100 \mus rectangular clicks, positive polarity', ...
    'FontWeight','bold','FontSize',12);
save_fig(f, fullfile(outDir,'stim_ClickTrain_waveform.png'));

spec_fig(c, fullfile(outDir,'stim_ClickTrain_spectrogram.png'), ...
    'ClickTrain — each click is broadband; the train repeats every 20 ms', ...
    256, [0 40]);

%% ----------------------------------------------------------- SweptSine
s = stimgen.SweptSine;
s.StartFrequency = 100;
s.StopFrequency  = 20000;
s.ChirpType      = "log-sine";
s.Duration       = 0.5;
s.update_signal;
wave_fig(s, fullfile(outDir,'stim_SweptSine_waveform.png'), ...
    'SweptSine — log-sine chirp, 100 Hz to 20 kHz over 500 ms');
spec_fig(s, fullfile(outDir,'stim_SweptSine_spectrogram.png'), ...
    'SweptSine — log-sine chirp traces an exponential frequency trajectory', ...
    2048, [0 24]);

%% ---------------------------------------------------------------- TORC
k = stimgen.TORC;
k.Duration     = 0.75;      % set before NumPeriods: T = Duration/NumPeriods,
k.LowFrequency = 125;       % and every ripple rate must be at least 1/T
k.Bandwidth    = 5;
k.NumPeriods   = 3;
k.Seed         = 7;         % fixed so the figure is reproducible
k.update_signal;
wave_fig(k, fullfile(outDir,'stim_TORC_waveform.png'), ...
    'TORC — 5 octaves from 125 Hz, three 250 ms periods of the ripple combination');
spec_fig(k, fullfile(outDir,'stim_TORC_spectrogram.png'), ...
    'TORC — moving spectral ripples drifting across the tonotopic axis', ...
    1024, [0.1 5], true);

%% ------------------------------------------------------------ SoundFile
% Any short speech recording will do; these ship with MATLAB / Audio Toolbox.
wav = which('FemaleSpeech-16-8-mono-3secs.wav');
if isempty(wav), wav = which('SpeechDFT-16-8-mono-5secs.wav'); end
if isempty(wav), wav = which('Counting-16-44p1-mono-15secs.wav'); end
if isempty(wav)
    warning('stimgen:make_wiki_figures:NoSampleAudio', ...
        'No sample sound file found on the MATLAB path; skipping the SoundFile figures.');
else
    sf = stimgen.SoundFile;
    sf.add_files(string(wav));
    sf.FileIndex = 1;
    sf.update_signal;
    [~, wavName] = fileparts(wav);
    wave_fig(sf, fullfile(outDir,'stim_SoundFile_waveform.png'), ...
        sprintf('SoundFile — "%s", resampled to the stimulus Fs', wavName));
    spec_fig(sf, fullfile(outDir,'stim_SoundFile_spectrogram.png'), ...
        'SoundFile — recorded speech: voiced harmonic stacks, formants and silent gaps', ...
        1024, [0 4]);
end

%% ---------------------------------------------------------------- Patch
p = stimgen.Patch.preset("PulsedTone");
p.Duration = 0.5;
if isprop(p,'Pulse1_Rate'), p.Pulse1_Rate = 10; end
p.update_signal;
wave_fig(p, fullfile(outDir,'stim_Patch_waveform.png'), ...
    'Patch — "PulsedTone" preset: a pulse train gating a tone oscillator');
spec_fig(p, fullfile(outDir,'stim_Patch_spectrogram.png'), ...
    'Patch — "PulsedTone": a single carrier switched on and off by the pulse component', ...
    1024, [0 8]);

fprintf('done.\n');
end

% ======================================================================= helpers

function f = new_fig(w, h)
% Size in pixels; exportgraphics treats that as inches at 96 dpi, so a
% 1000 px figure at 200 dpi lands at a little over 2000 px wide.
f = figure('Visible','off','Color','w','Units','pixels', ...
    'Position',[80 80 w h]);
end

function save_fig(f, fname)
exportgraphics(f, fname, 'Resolution', 200, 'BackgroundColor', 'white');
close(f);
d = dir(fname);
fprintf('  %-44s %6.0f kB\n', d.name, d.bytes/1024);
end

function draw_wave(ax, obj)
tms = obj.Time(:) * 1e3;   % seconds -> milliseconds, as everywhere in the GUIs
sig = obj.Signal(:);
plot(ax, tms, sig, 'Color',[0.10 0.35 0.70], 'LineWidth',0.6);
grid(ax,'on');
ax.XLim = [tms(1) tms(end)];             % signal fills the axis
pk = max(abs(sig));
if pk <= 0 || ~isfinite(pk), pk = 1; end
ax.YLim = [-1.08 1.08] * pk;             % rms-normalized classes peak well above 1
ax.Box = 'on';
ax.FontSize = 10;
ax.Layer = 'top';
xlabel(ax, 'time (ms)');
ylabel(ax, 'amplitude');
end

function wave_fig(obj, fname, ttl)
f = new_fig(1000, 300);
ax = axes(f, 'Position',[0.075 0.175 0.90 0.72]);
draw_wave(ax, obj);
title(ax, ttl, 'FontWeight','bold','FontSize',12);
save_fig(f, fname);
end

function spec_fig(obj, fname, ttl, nfft, fkHzLim, logFreq)
% nfft sets the time/frequency tradeoff and is chosen per stimulus: short for
% clicks, where onset timing is the point, long for chirps and FM, where the
% frequency trajectory is.
if nargin < 6 || isempty(logFreq), logFreq = false; end

sig = double(obj.Signal(:));
fs  = double(obj.Fs);
N   = numel(sig);

nfft = min(nfft, 2^floor(log2(N/4)));
win  = hann(nfft, 'periodic');
hop  = max(1, floor((N - nfft) / 1200));   % ~1200 time columns -> dense in time
hop  = min(hop, floor(nfft/2));            % keep the overlap high
noverlap = nfft - hop;

% Pad by half a window so the first and last frames are centred on t = 0 and
% t = end: the spectrogram then spans the whole signal with no blank margin.
% The padding is an odd (point) reflection, x(-t) = 2*x(0) - x(t), which
% continues the waveform smoothly; an even reflection puts a corner at each
% edge and zero padding fades them out, and both smear the edge frames.
pad  = floor(nfft/2);
pad  = min(pad, N-1);
sigp = [2*sig(1)   - flipud(sig(2:pad+1)); ...
        sig; ...
        2*sig(end) - flipud(sig(end-pad:end-1))];

% zero-pad the FFT beyond the window length for a smooth frequency axis
nfftPad = 4 * nfft;
[S, F, T] = spectrogram(sigp, win, noverlap, nfftPad, fs);
T = T - pad/fs;
P = 20*log10(abs(S) + eps);
P = P - max(P(:));

f = new_fig(1000, 400);
ax = axes(f, 'Position',[0.075 0.155 0.845 0.735]);
if isempty(fkHzLim), fkHzLim = [0 fs/2e3]; end
if logFreq
    % imagesc maps its image linearly between the YData limits and so cannot
    % be drawn on a log axis; surface carries the real coordinates.
    lo = max(fkHzLim(1), 2*F(2)/1e3);
    keep = F/1e3 >= lo/2 & F/1e3 <= fkHzLim(2)*2;
    surface(ax, T*1e3, F(keep)/1e3, zeros(sum(keep), numel(T)), P(keep,:), ...
        'EdgeColor','none');
    view(ax, 2);
    ax.YScale = 'log';
    ax.YLim = [lo fkHzLim(2)];
else
    imagesc(ax, T*1e3, F/1e3, P);
    axis(ax, 'xy');
    ax.YLim = fkHzLim;
end
colormap(ax, parula);
clim(ax, [-60 0]);
ax.XLim = [T(1) T(end)]*1e3;              % signal fills the time axis
ax.Box = 'on';
ax.FontSize = 10;
ax.Layer = 'top';
ax.TickDir = 'out';
xlabel(ax, 'time (ms)');
ylabel(ax, 'frequency (kHz)');
title(ax, ttl, 'FontWeight','bold','FontSize',12);
cb = colorbar(ax);
cb.Label.String = 'power (dB re peak)';
cb.FontSize = 9;
save_fig(f, fname);
end
