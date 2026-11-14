classdef DMRPaperTest < matlab.unittest.TestCase
    % What Escabi & Schreiner (2002, J Neurosci 22:4114) state about the
    % dynamic moving ripple and ripple noise, checked against stimgen.DMR at
    % the paper's parameters (the class defaults):
    %
    %   - Omega and Fm are flat over 0-4 cycles/octave and -350..350 Hz
    %     (Methods; Fig. 2A-C)
    %   - the long-term envelope correlation is
    %       sigma^2 sinc(2 Omega_max xi) sinc(2 F_max tau)            [Eq. 9]
    %     an "impulse-like central peak of width 3 msec and one-fourth
    %     octave" (Fig. 2D,E, far right)
    %   - ripple noise has the same long-term correlation, and compressing
    %     it by erf barely changes that (Methods: "close agreement")
    %   - sigma_DMR^2 = M^2/8 and sigma_RN^2 = M^2/12                  [Eq. 7-8]
    %   - the overall level is the per-carrier level + 10 log10(230) dB
    %   - at 44.1 kHz the parameter sequences are upsampled by 7350 (Omega,
    %     6 Hz) and 14700 (Fm, 3 Hz)
    %
    % DMRTest covers the mechanics (Eq. 1-5 as arithmetic, seeds, records);
    % this file covers the statistics those equations are said to have. The
    % tolerances come from simulating the method: they pass for a flat
    % trajectory and fail for one weighted toward mid-range (as
    % GeneratorVersion 1 was) or toward the limits (ErfScaling "AsPrinted").
    %
    % Trajectories do not depend on the carriers or on Fs, so the long ones
    % here are read from a stimulus with two carriers at 4 kHz, which costs
    % almost nothing to synthesize. Lines starting DMRPAPER are printed for
    % the CI log.
    %
    % Run from the repository root:
    %   addpath(pwd); results = runtests('tests');
    % See tests/README.md.

    properties
        Long   % ripple_trajectory of a 600 s default DMR, 200 samples/s
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'documentation', 'tools')));
        end

        function longTrajectory(testCase)
            s = trajectory_only_(600, 'Seed', 2002);
            testCase.Long = s.ripple_trajectory(120000);
        end
    end

    % ------------------------------------------------------------------ %
    methods (Test)

        function parametersAreFlatOverTheirRanges(testCase)
            % "both parameters were designed with uniformly (flat)
            % distributed amplitudes in the intervals 0-4 cycles per octave
            % for Omega and -350 to +350 Hz for Fm."
            tr = testCase.Long;
            check_flat_(testCase, tr.Omega, [0 4], 'Omega');
            check_flat_(testCase, tr.Fm, [-350 350], 'Fm');
        end

        function asPrintedScalingIsNotFlat(testCase)
            % The equations as printed, erf(x) on the knot sequence, put the
            % parameters near their limits more of the time: the variance is
            % well above a flat distribution's 1/12 of range^2. Pinned so the
            % class help's statement about the option stays true.
            s  = trajectory_only_(300, 'Seed', 2002, 'ErfScaling', "AsPrinted");
            tr = s.ripple_trajectory(60000);
            vOm = var(tr.Omega, 1) / 4^2;
            vFm = var(tr.Fm, 1) / 700^2;
            fprintf('DMRPAPER AsPrinted: variance/range^2 Omega %.4f, Fm %.4f (flat 0.0833)\n', vOm, vFm);
            testCase.verifyGreaterThan(vOm, 0.095);
            testCase.verifyGreaterThan(vFm, 0.095);
        end

        function longTermCorrelationIsEquation9(testCase)
            % Eq. 7 gives the instantaneous correlation of the DMR envelope
            % as sigma^2 cos(2 pi Omega xi + 2 pi Fm tau); averaged over the
            % parameters it is Eq. 9, sigma^2 sinc(2 Omega_max xi)
            % sinc(2 F_max tau), which holds exactly when Omega and Fm are
            % independent and flat. Its first zeros, 1/(2 F_max) = 1.43 ms
            % and 1/(2 Omega_max) = 1/8 octave either side of the origin,
            % are the "width 3 msec and one-fourth octave" of Fig. 2.
            tr  = testCase.Long;
            tau = 0:0.25e-3:6e-3;
            xi  = 0:1/64:0.5;

            Rt = arrayfun(@(l) mean(cos(2*pi .* tr.Fm    .* l)), tau);
            Rx = arrayfun(@(l) mean(cos(2*pi .* tr.Omega .* l)), xi);
            devT = max(abs(Rt - sinc_(2 * 350 .* tau)));
            devX = max(abs(Rx - sinc_(2 * 4 .* xi)));
            zT = first_zero_(tau, Rt);
            zX = first_zero_(xi, Rx);
            fprintf(['DMRPAPER Eq. 9: max |R - sinc| %.3f along tau, %.3f along xi; first zeros %.3f ms ' ...
                '(1.429) and %.4f octave (0.1250); central peak %.2f ms by %.3f octave\n'], ...
                devT, devX, 1e3 * zT, zX, 2e3 * zT, 2 * zX);

            testCase.verifyLessThan(devT, 0.05);
            testCase.verifyLessThan(devX, 0.05);
            testCase.verifyEqual(1e3 * zT, 1e3 / (2 * 350), 'AbsTol', 0.07);
            testCase.verifyEqual(zX, 1 / (2 * 4), 'AbsTol', 0.006);

            % Jointly: the two parameters are independent, so the correlation
            % at (tau, xi) is the product. (A little looser: it also carries
            % the record's residual asymmetry in Fm.)
            for l = [0.5e-3 1e-3]
                for d = [1/16 1/8]
                    R = mean(cos(2*pi .* (tr.Omega .* d + tr.Fm .* l)));
                    testCase.verifyEqual(R, sinc_(2 * 4 * d) * sinc_(2 * 350 * l), 'AbsTol', 0.07, ...
                        sprintf('tau = %g ms, xi = %g octave', 1e3 * l, d));
                end
            end
        end

        function rippleNoiseSharesTheLongTermCorrelation(testCase)
            % Ripple noise: the sum of 16 DMR envelopes has the DMR's
            % variance, M^2/8, and its long-term correlation; compressed by
            % erf (Eq. 3) it has the variance of a flat distribution, M^2/12,
            % and nearly the same correlation ("close agreement" in the
            % paper). Evaluated from the trajectories at one octave position
            % and four spectral displacements, at the paper's 4 kHz envelope
            % rate.
            M  = 30;
            L  = 16;
            fs = 4000;
            s  = trajectory_only_(60, 'Seed', 7, 'EnvelopeMode', "RippleNoise", ...
                'NumEnvelopes', L, 'ModulationDepth', M);
            tr = s.ripple_trajectory(60 * fs);
            testCase.assertEqual(tr.t(2) - tr.t(1), 1 / fs, 'AbsTol', 1e-12);

            % Eq. 2 and Eq. 3 from the trajectories, at any octave position.
            uncompressed = @(x) (M/2) .* sum(sin(2*pi .* tr.Omega .* x + tr.Phase), 1) ./ sqrt(L);
            compress     = @(sBar) (M/2) .* erf(sBar ./ (sqrt(2) .* M ./ sqrt(8)));

            % That is the class's envelope: at a carrier's own position it is
            % what envelope_at returns.
            first = 1:2000;
            mine  = compress(uncompressed(s.OctaveAxis(2)));
            S     = s.envelope_at(tr.t(first));
            testCase.verifyEqual(mine(first), S(2, :), 'AbsTol', 1e-9);

            x0  = 2;
            xis = [0 1/16 1/8 3/16 1/4];
            U = zeros(numel(xis), numel(tr.t));
            for q = 1:numel(xis)
                U(q, :) = uncompressed(x0 - xis(q));
            end
            C = compress(U);

            fprintf('DMRPAPER ripple noise variance: sum %.2f dB^2 (M^2/8 = %.2f), compressed %.2f (M^2/12 = %.2f)\n', ...
                var(U(1, :), 1), M^2/8, var(C(1, :), 1), M^2/12);
            testCase.verifyEqual(var(U(1, :), 1), M^2/8,  'RelTol', 0.06);
            testCase.verifyEqual(var(C(1, :), 1), M^2/12, 'RelTol', 0.06);

            lags = 0:20;                       % 0 .. 5 ms at 4 kHz
            acfT = @(v) arrayfun(@(k) mean(v(1 + k:end) .* v(1:end - k)), lags) ./ mean(v .^ 2);
            acfX = @(V) (V * V(1, :).' ./ size(V, 2)).' ./ mean(V(1, :) .^ 2);
            tU = acfT(U(1, :));   tC = acfT(C(1, :));
            xU = acfX(U);         xC = acfX(C);

            rmsT = sqrt(mean((tC - tU) .^ 2));
            rmsX = sqrt(mean((xC - xU) .^ 2));
            devT = max(abs(tC - sinc_(2 * 350 .* lags ./ fs)));
            devX = max(abs(xC - sinc_(2 * 4 .* xis)));
            fprintf(['DMRPAPER ripple noise correlation: compressed vs uncompressed rms %.3f (tau), %.3f (xi); ' ...
                'compressed vs Eq. 9 max %.3f (tau), %.3f (xi)\n'], rmsT, rmsX, devT, devX);
            testCase.verifyLessThan(rmsT, 0.03);
            testCase.verifyLessThan(rmsX, 0.03);
            testCase.verifyLessThan(devT, 0.08);
            testCase.verifyLessThan(devX, 0.08);
        end

        function overallLevelIsPerCarrierPlusTenLogN(testCase)
            % "Because the RN and DMR stimuli are each composed of 230
            % sinusoid carriers, the effective SPLs were 10 log10(230) =
            % 23.6 dB greater than these values" (the per-carrier levels).
            % The carriers add as powers: the power of the synthesized sum is
            % 230 times the mean power of one modulated carrier.
            s = stimgen.DMR('Fs', 44100, 'ApplyCalibration', false, 'ApplyWindow', false, ...
                'Duration', 1, 'Seed', 3);
            s.update_signal();
            r = s.generation_record();
            testCase.assertEqual(r.NumCarriers, 230);

            t = (0:3999) ./ 4000;                          % 1 s at the paper's envelope rate
            S = s.envelope_at(t);
            amplitude  = 10 .^ ((S - r.ModulationDepth/2) ./ 20);     % Eq. 5
            perCarrier = mean(amplitude .^ 2, 2) ./ 2;                % power of one modulated carrier
            gainDb = 10 * log10(r.RawRms^2 / mean(perCarrier));
            fprintf('DMRPAPER overall level re one carrier: %.2f dB (10*log10(230) = %.2f)\n', ...
                gainDb, 10 * log10(230));
            testCase.verifyEqual(gainDb, 10 * log10(230), 'AbsTol', 0.3);

            % Eq. 5: the linear envelope lies between 10^(-M/20) and 1.
            testCase.verifyLessThanOrEqual(max(amplitude(:)), 1 + 1e-12);
            testCase.verifyGreaterThanOrEqual(min(amplitude(:)), 10^(-r.ModulationDepth/20) - 1e-12);
        end

        function samplingFactorsAtThePapersRate(testCase)
            % "sampling rate of 3 Hz for Fm(t) and 6 Hz for Omega(t) ...
            % upsampled both signals to 44.1 kHz ... upsampling factor,
            % 14,700 for modulation rate and 7350 for ripple density".
            s = stimgen.DMR('Fs', 44100, 'ApplyCalibration', false, 'Duration', 0.05);
            s.update_signal();
            r = s.generation_record();
            testCase.verifyEqual(r.Fs / r.RateKnotRate, 14700);
            testCase.verifyEqual(r.Fs / r.RippleKnotRate, 7350);
            % The stated maximum rates of change are half the sampling rates.
            testCase.verifyEqual(s.ModulationRateChangeRate, r.RateKnotRate / 2);
            testCase.verifyEqual(s.RippleDensityChangeRate, r.RippleKnotRate / 2);
        end

        function figureScriptRuns(testCase)
            % documentation/tools/dmr_paper_figures draws the paper's
            % stimulus panels with the class, for comparison by eye. Here it
            % only has to run; what it draws is checked numerically above.
            try
                probe = figure('Visible', 'off');
                delete(probe);
            catch ME
                fprintf('DMRPAPER no figure on this runner, figure script not run: %s\n', ME.message);
                return
            end
            figs = dmr_paper_figures('Visible', "off", 'LongDuration', 30);
            testCase.addTeardown(@() delete(figs(isgraphics(figs))));
            testCase.verifyEqual(numel(figs), 2);
            testCase.verifyTrue(all(isgraphics(figs, 'figure')));
        end

    end
end


% ====================================================================== %

function s = trajectory_only_(duration, varargin)
% A generated DMR that costs almost nothing to synthesize: two carriers at
% 4 kHz. Its Omega(t), Fm(t) and Phi(t) are the ones any carrier bank and
% sample rate would get from the same seed and settings.
s = stimgen.DMR('Fs', 4000, 'ApplyCalibration', false, 'ApplyWindow', false, ...
    'LowFrequency', 500, 'HighFrequency', 1000, 'NumCarriers', 2, ...
    'Duration', duration, varargin{:});
s.update_signal();
end


function check_flat_(testCase, v, range, name)
% A long trajectory is flat over its range: variance 1/12 of range^2, and
% each tenth of the range holds a tenth of the time. The limits allow for
% the length of the record and for the mapping being exactly flat only on
% average over a knot interval (the interpolant's variance is 1 at a knot
% and 0.64 midway).
u = (v(:).' - range(1)) ./ (range(2) - range(1));
testCase.verifyGreaterThanOrEqual(min(u), 0, name);
testCase.verifyLessThanOrEqual(max(u), 1, name);

vr  = var(u, 1);
occ = histcounts(u, 0:0.1:1) ./ numel(u);
fprintf('DMRPAPER %s: variance/range^2 %.4f (flat 0.0833); time in each tenth of the range %s\n', ...
    name, vr, sprintf('%.3f ', occ));
testCase.verifyGreaterThan(vr, 0.0775, sprintf('%s is weighted toward mid-range', name));
testCase.verifyLessThan(vr, 0.0890, sprintf('%s is weighted toward its limits', name));
testCase.verifyGreaterThan(min(occ), 0.075, name);
testCase.verifyLessThan(max(occ), 0.125, name);
end


function y = sinc_(x)
% sin(pi x)/(pi x), with sinc_(0) = 1.
y = ones(size(x));
nz = x ~= 0;
y(nz) = sin(pi .* x(nz)) ./ (pi .* x(nz));
end


function z = first_zero_(lags, r)
% Where r first crosses zero, by linear interpolation between samples.
k = find(r <= 0, 1);
if isempty(k) || k == 1
    z = NaN;
    return
end
z = lags(k - 1) + (lags(k) - lags(k - 1)) * r(k - 1) / (r(k - 1) - r(k));
end
