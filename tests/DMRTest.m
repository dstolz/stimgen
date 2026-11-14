classdef DMRTest < matlab.unittest.TestCase
    % stimgen.DMR, the dynamic moving ripple / ripple noise generator
    % (Escabi & Schreiner 2002): that a waveform is a pure function of its
    % properties and seed, that the generation record is enough to rebuild
    % it, and that the envelope reported is the envelope that was played.
    %
    % Nearly every case uses a small configuration (13 carriers, half a
    % second, 48 kHz) so the file runs in seconds. The reference
    % implementations at the bottom are written from the formulas, not
    % copied from the class.
    %
    % Lines starting DMRCHECK, DMRTIMING and DMRGOLD are printed for the CI
    % log: which interp1 method the class's interpolant matches on this
    % MATLAB release, what synthesis costs, and the values the golden test
    % pins.
    %
    % Run from the repository root:
    %   addpath(pwd); results = runtests('tests');
    % See tests/README.md.

    methods (TestClassSetup)
        function addPackageRoot(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
        end
    end

    % ------------------------------------------------------------------ %
    methods (Test)

        function defaultsAreThePapers(testCase)
            % The class defaults are the values stated in the paper's
            % Methods; a change to one of them is a change to what "a DMR"
            % means here.
            s = stimgen.DMR;
            testCase.verifyEqual(s.LowFrequency, 500);
            testCase.verifyEqual(s.HighFrequency, 20000);
            testCase.verifyEqual(s.NumCarriers, 230);
            testCase.verifyEqual(s.EnvelopeMode, "DMR");
            testCase.verifyEqual(s.NumEnvelopes, 16);
            testCase.verifyEqual(s.RippleDensityMin, 0);
            testCase.verifyEqual(s.RippleDensityMax, 4);
            testCase.verifyEqual(s.RippleDensityChangeRate, 3);
            testCase.verifyEqual(s.ModulationRateMin, -350);
            testCase.verifyEqual(s.ModulationRateMax, 350);
            testCase.verifyEqual(s.ModulationRateChangeRate, 1.5);
            testCase.verifyEqual(s.ModulationDepth, 30);
            testCase.verifyEqual(s.CalibrationType, "filter");
            testCase.verifyEqual(s.Normalization, "rms");
        end

        function defaultCarrierGridIsThePapers(testCase)
            % 230 carriers from 500 Hz at the ratio the paper prints
            % (1.01617), which is 40^(1/230) and not 2^(1/43).
            s = stimgen.DMR('Fs', 48000, 'ApplyCalibration', false, 'Duration', 0.05);
            s.update_signal();
            f = s.CarrierFrequencies;
            testCase.verifyEqual(numel(f), 230);
            testCase.verifyEqual(f(1), 500);
            ratio = f(2:end) ./ f(1:end-1);
            testCase.verifyEqual(ratio, repmat(40^(1/230), 1, 229), 'RelTol', 1e-12);
            testCase.verifyEqual(round(ratio(1) * 1e5) / 1e5, 1.01617, 'AbsTol', 1e-12);
            testCase.verifyEqual(f(end), 20000 / 40^(1/230), 'RelTol', 1e-12);
            testCase.verifyLessThan(f(end), 20000);
            testCase.verifyEqual(s.OctaveAxis, log2(f ./ 500), 'AbsTol', 1e-12);

            % Knots at twice the stated maximum rates of change: 6 and 3 Hz,
            % one before time zero.
            r = s.generation_record();
            testCase.verifyEqual(r.RippleKnotRate, 6);
            testCase.verifyEqual(r.RateKnotRate, 3);
            testCase.verifyEqual(r.Envelope(1).RippleKnotTimes(1:3), [-1 0 1] ./ 6, 'AbsTol', 1e-15);
            testCase.verifyEqual(r.Envelope(1).RateKnotTimes(1:3),   [-1 0 1] ./ 3, 'AbsTol', 1e-15);
            testCase.verifyEqual(r.RippleDensityRange, [0 4]);
            testCase.verifyEqual(r.ModulationRateRange, [-350 350]);
            testCase.verifyEqual(r.NyquistMarginHz, 24000 - f(end), 'AbsTol', 1e-9);
        end

        function sameSeedSameSignal(testCase)
            a = small_('Seed', 3);  a.update_signal();
            b = small_('Seed', 3);  b.update_signal();
            testCase.verifyNotEmpty(a.Signal);
            testCase.verifyTrue(isequal(a.Signal, b.Signal), 'two objects, one seed, different signals');
            testCase.verifyFalse(a.generation_record().CacheHit);

            % Generated again, the synthesis is reused -- and is the same
            % waveform a fresh object makes.
            a.update_signal();
            testCase.verifyTrue(a.generation_record().CacheHit);
            testCase.verifyTrue(isequal(a.Signal, b.Signal), 'cached and fresh generations differ');

            c = small_('Seed', 4);  c.update_signal();
            testCase.verifyFalse(isequal(a.Signal, c.Signal), 'two seeds, one signal');
        end

        function globalRandomStreamIsUntouched(testCase)
            previous = rng;
            testCase.addTeardown(@() rng(previous));
            rng(20261114, 'twister');
            before = rng;

            s = small_('Seed', 1);
            s.update_signal();
            n = small_('Seed', 2, 'EnvelopeMode', "RippleNoise", 'NumEnvelopes', 3);
            n.update_signal();

            after = rng;
            testCase.verifyEqual(after.Seed, before.Seed);
            testCase.verifyTrue(isequal(after.State, before.State), ...
                'generating a DMR advanced the global random stream');
        end

        function seedMustBeANonnegativeInteger(testCase)
            % No "reseed randomly" value: a seed that was never recorded
            % cannot be reconstructed.
            testCase.verifyTrue(throws_(@() stimgen.DMR('Seed', -1)));
            testCase.verifyTrue(throws_(@() stimgen.DMR('Seed', 1.5)));
            testCase.verifyTrue(throws_(@() stimgen.DMR('Seed', [1 2 -3])));
            testCase.verifyFalse(throws_(@() stimgen.DMR('Seed', [0 1 4294967295])));
        end

        function interpolantIsCubicConvolution(testCase)
            % The trajectory between knots, before erf, is cubic convolution
            % (Keys, a = -1/2). Checked through the public trajectory against
            % a reference written from the kernel weights, and compared with
            % interp1 on this release -- the paper names interp1's 'cubic'
            % option, whose meaning has changed between releases.
            s = small_('Seed', 5, 'Duration', 2);
            s.update_signal();
            r  = s.generation_record();
            tr = s.ripple_trajectory(4001);
            e  = r.Envelope(1);
            u  = tr.t .* r.RippleKnotRate;            % in knot intervals
            jk = -1:numel(e.RippleKnots) - 2;         % knot positions, exactly uniform

            reference = map_(keys_(e.RippleKnots, u), r.ErfDivisor, r.RippleDensityRange);
            testCase.verifyEqual(tr.Omega, reference, 'AbsTol', 1e-12);

            names = ["v5cubic", "cubic", "pchip", "spline", "makima"];
            worst = nan(size(names));
            for k = 1:numel(names)
                try
                    g = interp1(jk, e.RippleKnots, u, char(names(k)));
                    worst(k) = max(abs(map_(g, r.ErfDivisor, r.RippleDensityRange) - tr.Omega));
                catch ME
                    fprintf('DMRCHECK interp1 ''%s'' failed on this release: %s\n', names(k), ME.message);
                end
                fprintf('DMRCHECK release %s: max |Omega - interp1(''%s'')| = %.3g cycles/octave\n', ...
                    version('-release'), names(k), worst(k));
            end
            testCase.verifyLessThan(worst(names == "v5cubic"), 1e-10, ...
                'the class''s interpolant is not interp1''s ''v5cubic'' (cubic convolution)');
            testCase.verifyLessThan(worst(names == "cubic"), 1e-10, ...
                'the class''s interpolant is not what interp1''s ''cubic'' does on this release');
        end

        function trajectoriesStayInRangeAndPhaseIsTheIntegral(testCase)
            s = small_('Seed', 2, 'Duration', 4, ...
                'RippleDensityMin', 0.5, 'RippleDensityMax', 3, ...
                'ModulationRateMin', -200, 'ModulationRateMax', 120);
            s.update_signal();
            r  = s.generation_record();
            tr = s.ripple_trajectory(8000);

            testCase.verifyGreaterThanOrEqual(min(tr.Omega), 0.5);
            testCase.verifyLessThanOrEqual(max(tr.Omega), 3);
            testCase.verifyGreaterThanOrEqual(min(tr.Fm), -200);
            testCase.verifyLessThanOrEqual(max(tr.Fm), 120);
            % It moves: not parked at one value.
            testCase.verifyGreaterThan(max(tr.Omega) - min(tr.Omega), 0.5);
            testCase.verifyGreaterThan(max(tr.Fm) - min(tr.Fm), 50);
            testCase.verifyEqual(tr.Phase(1), 0);

            % Phi(t) = 2 pi * integral of Fm, against MATLAB's adaptive
            % quadrature of the reference Fm, with the knots as waypoints.
            e  = r.Envelope(1);
            fm = @(tau) map_(keys_(e.RateKnots, tau .* r.RateKnotRate), ...
                r.ErfDivisor, r.ModulationRateRange);
            testCase.verifyEqual(tr.Fm, fm(tr.t), 'AbsTol', 1e-10);

            knots = (1:floor(4 * r.RateKnotRate)) ./ r.RateKnotRate;
            for i = [2 400 3999 6001 8000]
                tq  = tr.t(i);
                ref = 2*pi * integral(fm, 0, tq, 'Waypoints', knots(knots < tq), ...
                    'AbsTol', 1e-10, 'RelTol', 1e-11);
                testCase.verifyEqual(tr.Phase(i), ref, 'AbsTol', 1e-6, ...
                    sprintf('Phi at t = %g s', tq));
            end

            % The stored running integral at the knots is that same integral.
            for j = [1 2 7 12]
                tj  = j / r.RateKnotRate;
                ref = integral(fm, 0, tj, 'Waypoints', knots(knots < tj), ...
                    'AbsTol', 1e-10, 'RelTol', 1e-11);
                testCase.verifyEqual(e.RateKnotCycles(j + 1), ref, 'AbsTol', 1e-7, ...
                    sprintf('RateKnotCycles at knot %d', j));
            end
        end

        function envelopeIsBoundedWithTheStatedVariance(testCase)
            % |S| <= M/2 always. Over a long envelope the variance is M^2/8
            % for a DMR (a sine of amplitude M/2), and for ripple noise
            % M^2/12 with ErfScaling "Uniform" -- the figure the paper
            % reports -- against M^2/8.61 with the equations as printed.
            % A low sample rate and a narrow band keep 40 s cheap; the
            % statistics tolerances are loose because they are estimates.
            M = 30;
            args = {'Fs', 8000, 'LowFrequency', 500, 'HighFrequency', 2000, ...
                'NumCarriers', 12, 'Duration', 40, 'ModulationDepth', M, 'Seed', 7};
            t = (0:19999) ./ 500;      % 500 Hz grid over the 40 s

            d = small_(args{:});
            d.update_signal();
            S = d.envelope_at(t);
            testCase.verifyLessThanOrEqual(max(abs(S(:))), M/2 + 1e-12);
            fprintf('DMRCHECK DMR envelope variance %.2f dB^2 (M^2/8 = %.2f)\n', var(S(:), 1), M^2/8);
            testCase.verifyEqual(var(S(:), 1), M^2/8, 'RelTol', 0.05);

            expected = [M^2/12, M^2/8.610315];
            scaling  = ["Uniform", "AsPrinted"];
            for k = 1:2
                n = small_(args{:}, 'EnvelopeMode', "RippleNoise", 'NumEnvelopes', 16, ...
                    'ErfScaling', scaling(k));
                n.update_signal();
                S = n.envelope_at(t);
                testCase.verifyLessThanOrEqual(max(abs(S(:))), M/2 + 1e-12);
                fprintf('DMRCHECK ripple noise (%s) envelope variance %.2f dB^2 (expected %.2f)\n', ...
                    scaling(k), var(S(:), 1), expected(k));
                testCase.verifyEqual(var(S(:), 1), expected(k), 'RelTol', 0.10, ...
                    sprintf('ripple noise, ErfScaling %s', scaling(k)));
            end
        end

        function erfScalingIsRecordedAndChangesTheWaveform(testCase)
            a = small_('Seed', 3);
            a.update_signal();
            uniform = a.Signal;
            r = a.generation_record();
            testCase.verifyEqual(r.ErfScaling, "Uniform");
            testCase.verifyEqual(r.ErfDivisor, sqrt(2));

            a.ErfScaling = "AsPrinted";          % an edit regenerates
            r = a.generation_record();
            testCase.verifyFalse(r.CacheHit);
            testCase.verifyEqual(r.ErfScaling, "AsPrinted");
            testCase.verifyEqual(r.ErfDivisor, 1);
            testCase.verifyFalse(isequal(a.Signal, uniform));

            a.ErfScaling = "Uniform";
            testCase.verifyTrue(isequal(a.Signal, uniform));
        end

        function recordReconstructsTheWaveform(testCase)
            % The generation record alone -- knots, carriers, rules, no
            % random number generator -- rebuilds the synthesized sum, for a
            % DMR and for ripple noise. Ungated and uncalibrated, Signal is
            % that sum divided by its rms.
            configs = { ...
                {'Seed', 9}; ...
                {'Seed', 9, 'ErfScaling', "AsPrinted", 'ModulationDepth', 45}; ...
                {'Seed', 4, 'EnvelopeMode', "RippleNoise", 'NumEnvelopes', 3}};
            for c = 1:numel(configs)
                s = small_('ApplyWindow', false, configs{c}{:});
                s.update_signal();
                r = s.generation_record();
                testCase.assertTrue(r.Generated);

                y = reconstruct_(r);
                testCase.verifyEqual(sqrt(mean(y .^ 2)), r.RawRms, 'RelTol', 1e-11, ...
                    sprintf('config %d: RawRms', c));
                testCase.verifyEqual(max(abs(y)), r.RawPeak, 'RelTol', 1e-11, ...
                    sprintf('config %d: RawPeak', c));
                testCase.verifyEqual(s.Signal, y ./ sqrt(mean(y .^ 2)), 'AbsTol', 1e-10, ...
                    sprintf('config %d: Signal', c));
                testCase.verifyEqual(r.SignalRms, 1, 'RelTol', 1e-12);
            end
        end

        function gateIsRecordedAndAppliedAfterNormalization(testCase)
            % The record says what gate the waveform carries; the envelope
            % it reports does not include it.
            s = small_('Seed', 9, 'WindowDuration', 0.010);   % ApplyWindow defaults to true
            s.update_signal();
            r = s.generation_record();
            testCase.verifyTrue(r.Gate.Applied);
            testCase.verifyEqual(r.Gate.WindowFcn, "cos2");
            testCase.verifyEqual(r.Gate.WindowDuration, 0.010);
            testCase.verifyEqual(r.Gate.NumSamples, 480);

            y = reconstruct_(r);
            y = y ./ sqrt(mean(y .^ 2));
            g = hann(480).';
            y(1:240)         = y(1:240) .* g(1:240);
            y(end-239:end)   = y(end-239:end) .* g(241:480);
            testCase.verifyEqual(s.Signal, y, 'AbsTol', 1e-10);

            u = small_('Seed', 9, 'ApplyWindow', false);
            u.update_signal();
            testCase.verifyFalse(u.generation_record().Gate.Applied);
            testCase.verifyEqual(u.generation_record().Gate.NumSamples, 0);
            tq = [0 0.1 0.2 0.3 0.4 0.5];
            testCase.verifyEqual(u.envelope_at(tq), s.envelope_at(tq));
        end

        function dynamicSpectrumIsTheEnvelopeThatWasPlayed(testCase)
            M = 30;
            s = small_('Seed', 6, 'ModulationDepth', M);
            s.update_signal();

            [S, t, x] = s.dynamic_spectrum(50);
            testCase.verifySize(S, [13 50]);
            testCase.verifyEqual(t, (0:49) .* (0.5 / 50), 'AbsTol', 1e-15);
            testCase.verifyEqual(x, s.OctaveAxis);

            % The coarse grid and chosen instants are one function of time.
            testCase.verifyTrue(isequal(S, s.envelope_at(t)));

            % Eq. 1, from the reported trajectories.
            tr = s.ripple_trajectory(50);
            testCase.verifyEqual(S, (M/2) .* sin(2*pi .* (x(:) * tr.Omega) + tr.Phase), 'AbsTol', 1e-9);

            % At the sample instants it is the envelope synthesis used: the
            % record's reconstruction, which rebuilds Signal, evaluates the
            % same trajectories (recordReconstructsTheWaveform).
            n  = [0 1 999 23999];
            Sn = s.envelope_at(n ./ 48000);
            testCase.verifySize(Sn, [13 4]);

            testCase.verifyError(@() s.envelope_at(0.6), 'stimgen:DMR:TimeOutOfRange');
            testCase.verifyError(@() s.envelope_at(-0.1), 'stimgen:DMR:TimeOutOfRange');
        end

        function rangesAndNyquistAreChecked(testCase)
            % The default band (top carrier 19.7 kHz) does not fit under a
            % 30 kHz rate.
            s = stimgen.DMR('Fs', 30000, 'ApplyCalibration', false, 'Duration', 0.05);
            testCase.verifyError(@() s.update_signal(), 'stimgen:DMR:BandwidthExceedsNyquist');

            s = small_('LowFrequency', 9000);              % above HighFrequency (8 kHz)
            testCase.verifyError(@() s.update_signal(), 'stimgen:DMR:InvalidRange');
            s = small_('RippleDensityMin', 5);             % above RippleDensityMax (4)
            testCase.verifyError(@() s.update_signal(), 'stimgen:DMR:InvalidRange');
            s = small_('ModulationRateMax', -400);         % below ModulationRateMin (-350)
            testCase.verifyError(@() s.update_signal(), 'stimgen:DMR:InvalidRange');

            % The paper's band generates at the rates the suite and the
            % paper use.
            for fs = [44100 48000 97656.25]
                s = stimgen.DMR('Fs', fs, 'ApplyCalibration', false, 'Duration', 0.02);
                s.update_signal();
                testCase.verifyEqual(numel(s.Signal), round(fs * 0.02), sprintf('%g Hz', fs));
            end
        end

        function seedIsTheVariantAxis(testCase)
            s = small_('Seed', [11 12 13]);
            info = s.get_variant_info();
            testCase.verifyEqual(info.NumCombinations, 3);
            testCase.verifyEqual(info.PropertyNames, "Seed");

            % Pinned on a copy, as the combination viewer and the envelope
            % export generate: each combination carries its own seed.
            c = copy(s);
            c.VariantReselectOnUpdate = false;
            sig = cell(1, 3);
            for k = 1:3
                c.set_variant_index(k);
                r = c.generation_record();
                testCase.verifyEqual(r.Seed, 10 + k);
                testCase.verifyEqual(r.VariantIndex, k);
                testCase.verifyEqual(r.GeneratedVariantIndex, k);
                testCase.verifyEqual(r.VariantValues.Seed, 10 + k);
                sig{k} = c.Signal;
            end
            testCase.verifyFalse(isequal(sig{1}, sig{2}));
            testCase.verifyFalse(isequal(sig{2}, sig{3}));

            % A variant is the segment a scalar seed of the same value makes.
            one = small_('Seed', 12);
            one.update_signal();
            testCase.verifyTrue(isequal(one.Signal, sig{2}));

            % The source was not touched, and a run takes the seeds in
            % Serial order.
            testCase.verifyEmpty(s.Signal);
            s.update_signal();
            testCase.verifyEqual(s.generation_record().Seed, 11);
            s.update_signal();
            testCase.verifyEqual(s.generation_record().Seed, 12);
        end

        function drawsAreIndependentAcrossQuantities(testCase)
            % One substream per quantity: more carriers, more envelopes or a
            % longer segment leave the other draws as they were.
            a = small_('Seed', 5);
            a.update_signal();
            ra = a.generation_record();

            b = small_('Seed', 5, 'NumCarriers', 17);
            b.update_signal();
            rb = b.generation_record();
            testCase.verifyEqual(rb.CarrierPhases(1:13), ra.CarrierPhases);
            testCase.verifyEqual(rb.Envelope(1).RippleKnots, ra.Envelope(1).RippleKnots);
            testCase.verifyEqual(rb.Envelope(1).RateKnots, ra.Envelope(1).RateKnots);

            c = small_('Seed', 5, 'Duration', 1.5);
            c.update_signal();
            rc = c.generation_record();
            nOm = numel(ra.Envelope(1).RippleKnots);
            nFm = numel(ra.Envelope(1).RateKnots);
            testCase.verifyGreaterThan(numel(rc.Envelope(1).RippleKnots), nOm);
            testCase.verifyEqual(rc.Envelope(1).RippleKnots(1:nOm), ra.Envelope(1).RippleKnots);
            testCase.verifyEqual(rc.Envelope(1).RateKnots(1:nFm), ra.Envelope(1).RateKnots);
            testCase.verifyEqual(rc.CarrierPhases, ra.CarrierPhases);
            % So the longer segment starts with the shorter one's envelope.
            t = linspace(0, 0.5, 41);
            testCase.verifyEqual(c.envelope_at(t), a.envelope_at(t), 'AbsTol', 1e-12);

            d = small_('Seed', 5, 'EnvelopeMode', "RippleNoise", 'NumEnvelopes', 3);
            d.update_signal();
            rd = d.generation_record();
            testCase.verifyEqual(numel(rd.Envelope), 3);
            testCase.verifyEqual(rd.Envelope(1).RippleKnots, ra.Envelope(1).RippleKnots);
            testCase.verifyEqual(rd.Envelope(1).RateKnots, ra.Envelope(1).RateKnots);
            testCase.verifyFalse(isequal(rd.Envelope(2).RateKnots, rd.Envelope(1).RateKnots));
            testCase.verifyFalse(isequal(rd.Envelope(3).RippleKnots, rd.Envelope(2).RippleKnots));
            testCase.verifyEqual(rd.CarrierPhases, ra.CarrierPhases);

            % Knots are normal draws, not yet mapped onto a range.
            testCase.verifyGreaterThan(max(abs(rc.Envelope(1).RippleKnots)), 0.5);
        end

        function synthesisIsReusedOnlyWhenNothingItDependsOnChanged(testCase)
            s = small_('Seed', 1);
            s.update_signal();
            testCase.verifyFalse(s.generation_record().CacheHit);

            % Level, gate and (in DMR mode) the ripple-noise envelope count
            % do not enter the synthesized sum.
            s.SoundLevel = 70;
            testCase.verifyTrue(s.generation_record().CacheHit, 'SoundLevel');
            s.WindowDuration = 0.004;
            testCase.verifyTrue(s.generation_record().CacheHit, 'WindowDuration');
            s.ApplyWindow = false;
            testCase.verifyTrue(s.generation_record().CacheHit, 'ApplyWindow');
            s.NumEnvelopes = 8;
            testCase.verifyTrue(s.generation_record().CacheHit, 'NumEnvelopes in DMR mode');

            changes = { ...
                'LowFrequency', 600; 'HighFrequency', 9000; 'NumCarriers', 14; ...
                'RippleDensityMin', 0.5; 'RippleDensityMax', 3; 'RippleDensityChangeRate', 2; ...
                'ModulationRateMin', -100; 'ModulationRateMax', 100; 'ModulationRateChangeRate', 1; ...
                'ModulationDepth', 45; 'Seed', 2; 'Duration', 0.4; 'Fs', 44100; ...
                'ErfScaling', "AsPrinted"; 'EnvelopeMode', "RippleNoise"; 'NumEnvelopes', 3};
            for k = 1:size(changes, 1)
                name   = changes{k, 1};
                before = s.Signal;
                s.(name) = changes{k, 2};
                r = s.generation_record();
                testCase.assertTrue(r.Generated, name);
                testCase.verifyFalse(r.CacheHit, name);
                testCase.verifyFalse(isequal(s.Signal, before), name);
            end
        end

        function roundTripKeepsTheWaveform(testCase)
            % Restored from its struct, a DMR makes the same waveform: the
            % struct holds everything synthesis depends on.
            s = small_('Seed', [21 22], 'EnvelopeMode', "RippleNoise", 'NumEnvelopes', 2, ...
                'ErfScaling', "AsPrinted", 'ModulationDepth', 45, ...
                'RippleDensityMax', 2, 'ModulationRateMin', -64, 'ModulationRateMax', 64);
            s.update_signal();                       % combination 1
            S = s.toStruct();
            testCase.verifyEqual(S.Seed, [21 22]);
            testCase.verifyEqual(S.ErfScaling, "AsPrinted");

            s2 = stimgen.StimType.fromStruct(S);     % generated once: combination 1
            testCase.verifyClass(s2, 'stimgen.DMR');
            testCase.verifyEqual(s2.generation_record().Seed, 21);
            testCase.verifyTrue(isequal(s2.Signal, s.Signal));
        end

        function exportedEnvelopeIsTheOnePlayed(testCase)
            % export_envelope writes, per seed, the envelope a stimulus
            % pinned to that seed reports -- and leaves the object it was
            % called on exactly as it was.
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            s = small_('Seed', [31 32 33]);
            s.update_signal();                              % combination 1
            sig = s.Signal;

            ffn = s.export_envelope(fullfile(tmp.Folder, 'env'), 'SampleRate', 1000);
            testCase.verifyTrue(endsWith(ffn, ".mat"));
            testCase.verifyTrue(isfile(ffn));

            testCase.verifyTrue(isequal(s.Signal, sig), 'the export changed the source Signal');
            testCase.verifyEqual(s.get_variant_info().ActiveIndex, 1);

            L = load(ffn);
            testCase.verifyEqual(L.FormatVersion, 1);
            testCase.verifyEqual(L.GeneratorVersion, stimgen.DMR.GeneratorVersion);
            testCase.verifyEqual(L.EnvelopeFs, 1000);
            testCase.verifyFalse(L.Gated);
            testCase.verifyEqual(L.Seed, [31 32 33]);
            testCase.verifyEqual(L.VariantIndex, 1:3);
            testCase.verifyEqual(L.CombinationVariables, ["C0001" "C0002" "C0003"]);

            c = L.C0002;
            testCase.verifyEqual(c.Seed, 32);
            testCase.verifyEqual(c.VariantIndex, 2);
            testCase.verifyEqual(c.Time, (0:500) ./ 1000, 'AbsTol', 1e-15);   % 0 .. 0.5 s
            testCase.verifySize(c.Envelope, [13 501]);
            testCase.verifySize(c.Omega, [1 501]);
            testCase.verifySize(c.Fm, [1 501]);
            testCase.verifyEqual(c.Phase(1), 0);
            testCase.verifyEqual(c.Record.Seed, 32);
            testCase.verifyEqual(c.Record.GeneratorVersion, stimgen.DMR.GeneratorVersion);

            one = small_('Seed', 32);
            one.update_signal();
            testCase.verifyEqual(c.Envelope, one.envelope_at(c.Time));
            testCase.verifyEqual(c.OctaveAxis, one.OctaveAxis);
            testCase.verifyEqual(c.CarrierFrequencies, one.CarrierFrequencies);
            testCase.verifyEqual(L.RawRms(2), one.RawRms);
            testCase.verifyEqual(L.RawPeak(2), one.RawPeak);
            % Eq. 1 from the exported trajectories.
            testCase.verifyEqual(c.Envelope, ...
                15 .* sin(2*pi .* (c.OctaveAxis(:) * c.Omega) + c.Phase), 'AbsTol', 1e-9);

            % The file names the stimulus it came from.
            r = stimgen.StimType.fromStruct(L.Source);
            testCase.verifyClass(r, 'stimgen.DMR');
            testCase.verifyEqual(r.Seed, [31 32 33]);

            % The source's selection order went on undisturbed.
            s.update_signal();
            testCase.verifyEqual(s.generation_record().Seed, 32);

            % A subset, at another rate, into a file that already exists.
            ffn2 = s.export_envelope(ffn, 'Combinations', 3, 'SampleRate', 800);
            L2 = load(ffn2);
            testCase.verifyEqual(L2.Seed, 33);
            testCase.verifyEqual(L2.CombinationVariables, "C0003");
            testCase.verifyFalse(isfield(L2, 'C0001'), 'the earlier export was not replaced');
            testCase.verifyEqual(L2.EnvelopeFs, 800);

            % Below twice the fastest modulation rate (350 Hz) it would alias.
            low = fullfile(tmp.Folder, 'low.mat');
            testCase.verifyError(@() s.export_envelope(low, 'SampleRate', 600), ...
                'stimgen:DMR:EnvelopeRateTooLow');
            testCase.verifyFalse(isfile(low), 'a refused export left a file behind');
            testCase.verifyError(@() s.export_envelope(low, 'Combinations', 4), ...
                'stimgen:DMR:CombinationOutOfRange');
        end

        function reportsCostAndGoldenCandidates(testCase)
            % Printed for the CI log. The timing lines are what synthesis
            % costs on this machine (the class runs inside StimPlayer's
            % timer between trials); the DMRGOLD lines are the values the
            % golden test pins for GeneratorVersion 1.
            d = stimgen.DMR('ApplyCalibration', false, 'Duration', 1);   % paper band, default Fs
            d.update_signal();
            r = d.generation_record();
            fprintf('DMRTIMING DMR, %d carriers, %.2f Hz: %.2f s per second of stimulus\n', ...
                r.NumCarriers, r.Fs, r.GenerationSeconds / r.Duration);
            d.update_signal();
            fprintf('DMRTIMING same, reused from the cache: %.3f s\n', d.generation_record().GenerationSeconds);

            n = stimgen.DMR('ApplyCalibration', false, 'Duration', 0.25, ...
                'EnvelopeMode', "RippleNoise");
            n.update_signal();
            r = n.generation_record();
            fprintf('DMRTIMING ripple noise, %d envelopes, %d carriers, %.2f Hz: %.2f s per second of stimulus\n', ...
                r.NumEnvelopes, r.NumCarriers, r.Fs, r.GenerationSeconds / r.Duration);
            testCase.verifyNotEmpty(n.Signal);

            g = small_('Seed', 1, 'ApplyWindow', false);
            g.update_signal();
            r = g.generation_record();
            fprintf('DMRGOLD version %d release %s normal transform %s\n', ...
                r.GeneratorVersion, version('-release'), r.NormalTransform);
            fprintf('DMRGOLD CarrierPhases(1:3) = [%.17g %.17g %.17g]\n', r.CarrierPhases(1:3));
            fprintf('DMRGOLD RippleKnots(1:3)   = [%.17g %.17g %.17g]\n', r.Envelope(1).RippleKnots(1:3));
            fprintf('DMRGOLD RateKnots(1:3)     = [%.17g %.17g %.17g]\n', r.Envelope(1).RateKnots(1:3));
            fprintf('DMRGOLD RateKnotCycles(2:3)= [%.17g %.17g]\n', r.Envelope(1).RateKnotCycles(2:3));
            fprintf('DMRGOLD RawRms = %.17g  RawPeak = %.17g\n', r.RawRms, r.RawPeak);
            fprintf('DMRGOLD Signal([1 2 1000 24000]) = [%.17g %.17g %.17g %.17g]\n', g.Signal([1 2 1000 24000]));
        end

    end
end


% ====================================================================== %

function s = small_(varargin)
% A DMR small enough to generate in milliseconds: 13 carriers over four
% octaves, half a second at 48 kHz, uncalibrated.
s = stimgen.DMR('Fs', 48000, 'ApplyCalibration', false, 'Duration', 0.5, ...
    'NumCarriers', 13, 'HighFrequency', 8000, varargin{:});
end


function tf = throws_(fcn)
tf = false;
try
    fcn();
catch
    tf = true;
end
end


function g = keys_(z, u)
% Cubic convolution (Keys, a = -1/2) written from the kernel weights.
% z(1) is the knot at u = -1, z(2) the knot at u = 0, and so on; u is in
% knot intervals.
% Any shape of u: the knots are looked up into u's shape, so a caller such
% as integral may pass a row or a column.
j = floor(u);
s = u - j;
i = j + 2;
at = @(k) reshape(z(k), size(k));
g = 0.5 .* ( (-s.^3 + 2.*s.^2 - s)     .* at(i - 1) ...
           + (3.*s.^3 - 5.*s.^2 + 2)   .* at(i) ...
           + (-3.*s.^3 + 4.*s.^2 + s)  .* at(i + 1) ...
           + (s.^3 - s.^2)             .* at(i + 2) );
end


function v = map_(g, divisor, range)
% erf onto -1..1, then linearly onto the range.
v = range(1) + (range(2) - range(1)) .* (erf(g ./ divisor) + 1) ./ 2;
end


function y = reconstruct_(r)
% The synthesized sum (before normalization, calibration and gate) rebuilt
% from a generation record alone.
t = (0:r.N - 1) ./ r.Fs;
L = r.NumEnvelopes;
M = r.ModulationDepth;

om  = zeros(L, r.N);
cyc = zeros(L, r.N);
u   = t .* r.RateKnotRate;
j   = floor(u);
s   = u - j;
for l = 1:L
    e = r.Envelope(l);
    om(l, :) = map_(keys_(e.RippleKnots, t .* r.RippleKnotRate), r.ErfDivisor, r.RippleDensityRange);
    % Integral of Fm from the knot to t by the recorded quadrature rule,
    % added to the recorded running integral at the knot.
    acc = zeros(1, r.N);
    for q = 1:numel(r.QuadratureNodes)
        fm  = map_(keys_(e.RateKnots, j + s .* r.QuadratureNodes(q)), r.ErfDivisor, r.ModulationRateRange);
        acc = acc + r.QuadratureWeights(q) .* fm;
    end
    cyc(l, :) = e.RateKnotCycles(j + 1) + (s ./ r.RateKnotRate) .* acc;
end

y = zeros(1, r.N);
for k = 1:numel(r.CarrierFrequencies)
    ripples = sin(2*pi .* (om .* r.OctaveAxis(k) + cyc));
    if r.EnvelopeMode == "RippleNoise"
        sBar = (M/2) .* sum(ripples, 1) ./ sqrt(L);
        S    = (M/2) .* erf(sBar ./ (r.ErfDivisor .* M ./ sqrt(8)));
    else
        S = (M/2) .* ripples;
    end
    y = y + 10.^((S - M/2) ./ 20) .* sin(2*pi .* r.CarrierFrequencies(k) .* t + r.CarrierPhases(k));
end
end
