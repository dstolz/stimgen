function figs = dmr_paper_figures(options)
% figs = dmr_paper_figures()
% figs = dmr_paper_figures(Seed=1, Visible="on", LongDuration=600)
% Draw, with stimgen.DMR, the stimulus panels of Escabi & Schreiner (2002,
% J Neurosci 22:4114) Figures 1 and 2, for comparison with the paper by eye.
%
% A realization is random, so no panel can match the paper's stripe for
% stripe. What should match is the kind of picture and its scales, and --
% in the second figure -- the statistics the paper states: parameters flat
% over their ranges, and a long-term envelope correlation that is the
% product of two sincs (Eq. 9). tests/DMRPaperTest.m checks those numbers;
% this draws them.
%
% Figure 1 (the paper's Fig. 1C,D): the envelope of a dynamic moving ripple
% and of ripple noise, 0-0.7 s, 0-3 octaves above 500 Hz, with the caption's
% 70 Hz maximum temporal modulation rate and otherwise the paper's
% parameters (the class defaults: 230 carriers over 500-20,000 Hz, ripple
% density 0-4 cycles/octave, 30 dB modulation depth, 16 envelopes for the
% noise).
%
% Figure 2 (the paper's Fig. 2A-C and the "global correlation" of 2D):
%   - Omega(t) and Fm(t) over 15 s, and the same 15 s as a path through
%     ripple space
%   - how Omega and Fm are distributed over LongDuration seconds, against a
%     flat distribution
%   - the long-term correlation along tau and along xi, against
%     sinc(2 F_max tau) and sinc(2 Omega_max xi)
% The paper's instantaneous-correlation panels (Fig. 2D, left three) are
% Eq. 7 at three chosen parameter pairs and are not redrawn.
%
% The trajectories do not depend on the carriers or the sample rate, so the
% second figure reads them from a stimulus with two carriers at 4 kHz, which
% costs almost nothing to synthesize.
%
% Parameters (name-value):
%   Seed         - seed of the realizations drawn (default 1)
%   Visible      - "on" (default) or "off"
%   LongDuration - seconds of trajectory behind the distribution and
%                  correlation panels (default 600)
%
% Returns:
%   figs - the two figure handles
%
% The repository root and this folder must be on the path:
%   addpath(pwd); addpath(fullfile(pwd,'documentation','tools'))
%   dmr_paper_figures
arguments
    options.Seed         (1,1) double {mustBeInteger, mustBeNonnegative} = 1
    options.Visible      (1,1) string {mustBeMember(options.Visible, ["on","off"])} = "on"
    options.LongDuration (1,1) double {mustBePositive, mustBeFinite} = 600
end
vis = char(options.Visible);

% ------------------------------------------------------------------ %
% Figure 1: envelopes, at the Fig. 1 caption's 70 Hz maximum modulation rate
% ------------------------------------------------------------------ %
shared = {'Fs', 44100, 'ApplyCalibration', false, 'Duration', 0.7, ...
          'ModulationRateMin', -70, 'ModulationRateMax', 70, 'Seed', options.Seed};
ripple = stimgen.DMR(shared{:});
noise  = stimgen.DMR(shared{:}, 'EnvelopeMode', "RippleNoise");
ripple.update_signal();
noise.update_signal();

t = (0:2799) ./ 4000;          % 0.7 s at the paper's 4 kHz envelope rate
figs(1) = figure('Visible', vis, 'Name', 'Escabi & Schreiner 2002, Fig. 1C,D with stimgen.DMR', ...
    'Color', 'w', 'Position', [100 100 900 380]);
titles = {'Dynamic ripple', 'Ripple noise'};
stims  = {ripple, noise};
for k = 1:2
    [S, x] = stims{k}.envelope_at(t);
    show = x <= 3;
    ax = subplot(1, 2, k, 'Parent', figs(1));
    imagesc(ax, t, x(show), S(show, :));
    set(ax, 'YDir', 'normal', 'CLim', [-15 15]);
    colormap(ax, jet(256));
    xlabel(ax, 'Time (s)');
    ylabel(ax, 'Octaves above 500 Hz');
    title(ax, titles{k});
    c = colorbar(ax);
    c.Label.String = 'envelope (dB)';
end

% ------------------------------------------------------------------ %
% Figure 2: parameter trajectories and what they add up to
% ------------------------------------------------------------------ %
cheap = {'Fs', 4000, 'ApplyCalibration', false, 'ApplyWindow', false, ...
         'LowFrequency', 500, 'HighFrequency', 1000, 'NumCarriers', 2, 'Seed', options.Seed};
short = stimgen.DMR(cheap{:}, 'Duration', 15);
short.update_signal();
tr15 = short.ripple_trajectory(15 * 200);

long = stimgen.DMR(cheap{:}, 'Duration', options.LongDuration);
long.update_signal();
trL = long.ripple_trajectory(round(options.LongDuration * 200));

omMax = short.RippleDensityMax;
fmMax = short.ModulationRateMax;

figs(2) = figure('Visible', vis, 'Name', 'Escabi & Schreiner 2002, Fig. 2 with stimgen.DMR', ...
    'Color', 'w', 'Position', [120 80 1100 760]);

% A, B: the trajectories over 15 s
ax = subplot(3, 3, [1 2], 'Parent', figs(2));
plot(ax, tr15.t, tr15.Omega, 'k');
ylim(ax, [short.RippleDensityMin omMax]);
xlim(ax, [0 15]);
ylabel(ax, '\Omega (cycles/octave)');
title(ax, 'Ripple parameters (15 s)');

ax = subplot(3, 3, [4 5], 'Parent', figs(2));
plot(ax, tr15.t, tr15.Fm, 'k');
ylim(ax, [short.ModulationRateMin fmMax]);
xlim(ax, [0 15]);
ylabel(ax, 'F_m (Hz)');
xlabel(ax, 'Time (s)');

% C: the same 15 s through ripple space
ax = subplot(3, 3, [3 6], 'Parent', figs(2));
plot(ax, tr15.Fm, tr15.Omega, 'k');
xlim(ax, [short.ModulationRateMin fmMax]);
ylim(ax, [short.RippleDensityMin omMax]);
xlabel(ax, 'F_m (Hz)');
ylabel(ax, '\Omega (cycles/octave)');
title(ax, 'Ripple space (15 s)');

% How the parameters are distributed over the long record, against flat
ax = subplot(3, 3, 7, 'Parent', figs(2));
edges = linspace(0, 1, 21);
uOm = (trL.Omega - short.RippleDensityMin) ./ (omMax - short.RippleDensityMin);
uFm = (trL.Fm - short.ModulationRateMin) ./ (fmMax - short.ModulationRateMin);
centers = (edges(1:end-1) + edges(2:end)) ./ 2;
plot(ax, centers, histcounts(uOm, edges) ./ numel(uOm) .* 20, 'b-o', ...
         centers, histcounts(uFm, edges) ./ numel(uFm) .* 20, 'r-s', ...
         [0 1], [1 1], 'k--');
ylim(ax, [0 2]);
xlabel(ax, 'position in range (0 = min, 1 = max)');
ylabel(ax, 'density re flat');
legend(ax, {'\Omega', 'F_m', 'flat'}, 'Location', 'south');
title(ax, sprintf('Distribution over %g s', options.LongDuration));

% Long-term correlation along tau and along xi, against Eq. 9
tau = (0:0.1:8) .* 1e-3;
xi  = 0:1/128:0.6;
Rt  = arrayfun(@(l) mean(cos(2*pi .* trL.Fm    .* l)), tau);
Rx  = arrayfun(@(l) mean(cos(2*pi .* trL.Omega .* l)), xi);

ax = subplot(3, 3, 8, 'Parent', figs(2));
plot(ax, tau .* 1e3, Rt, 'k', tau .* 1e3, sinc_(2 * fmMax .* tau), 'r--');
xlabel(ax, 'delay \tau (ms)');
ylabel(ax, 'correlation');
legend(ax, {'stimgen.DMR', 'sinc(2 F_{max} \tau)'}, 'Location', 'northeast');
title(ax, 'Long-term correlation in time');
grid(ax, 'on');

ax = subplot(3, 3, 9, 'Parent', figs(2));
plot(ax, xi, Rx, 'k', xi, sinc_(2 * omMax .* xi), 'r--');
xlabel(ax, 'displacement \xi (octaves)');
ylabel(ax, 'correlation');
legend(ax, {'stimgen.DMR', 'sinc(2 \Omega_{max} \xi)'}, 'Location', 'northeast');
title(ax, 'Long-term correlation in frequency');
grid(ax, 'on');
end


function y = sinc_(x)
% sin(pi x)/(pi x), with sinc_(0) = 1.
y = ones(size(x));
nz = x ~= 0;
y(nz) = sin(pi .* x(nz)) ./ (pi .* x(nz));
end
