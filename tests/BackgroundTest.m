classdef BackgroundTest < matlab.unittest.TestCase
    % The ongoing background a stimulus is embedded in, and the stimuli that
    % are a modulation of it (documentation/stimgen_Background.md).
    %
    % What is pinned here:
    %   - a stimulus with no background is exactly what it always was, and a
    %     struct saved before the background properties existed loads as one;
    %   - the noise loop: its length, its level (the rms a stimgen.Noise at
    %     that SoundLevel has), its band, the seam, its seed;
    %   - a tone background's amplitude is the table's voltage;
    %   - Key says when two stimuli share a background, and a background
    %     setting the chosen type does not use is never a variant axis;
    %   - embedded_signal is the background plus the stimulus, sample for
    %     sample, and the AM / gap / FM operators are their closed forms;
    %   - a modulation's level is carrier-referenced, and a level check knows
    %     the offset that follows from that.
    %
    % No GUI, no audio device, no hardware.
    %
    % Run from the repository root:
    %   addpath(pwd); results = runtests('tests');
    % See tests/README.md.

    properties (Constant)
        Fs = 48000
    end

    methods (TestClassSetup)
        function addPackageRoot(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
        end
    end

    methods (TestMethodSetup)
        function seed(testCase)
            previous = rng;
            testCase.addTeardown(@() rng(previous));
            rng(20261114, 'twister');
        end
    end

    % ------------------------------------------------------------------ %
    methods (Test)

        function noBackgroundIsTheStimulusAsItWas(testCase)
            % Every class the designer offers, at its defaults. The ones that
            % are a sound of their own have no background and embed by
            % addition; the background modulations have one and add nothing.
            names = stimgen.StimType.list();
            for k = 1:numel(names)
                cls = ['stimgen.' names{k}];
                obj = feval(cls, 'Fs', testCase.Fs, 'ApplyCalibration', false);
                obj.update_signal();
                E = obj.get_embedding();
                testCase.verifyEqual(numel(E.Signal), numel(obj.Signal), cls);

                if isa(obj, 'stimgen.BackgroundModulation')
                    testCase.verifyEqual(E.Mode, "modulate", cls);
                    testCase.verifyFalse(any(E.Signal), cls);
                    testCase.verifyNotEmpty(E.Background, cls);
                    testCase.verifyTrue(~isempty(E.Gain) || ~isempty(E.Phase), cls);
                else
                    testCase.verifyEqual(obj.Background, "None", cls);
                    testCase.verifyEmpty(obj.get_background(), cls);
                    testCase.verifyEqual(E.Mode, "add", cls);
                    testCase.verifyEqual(E.Signal, obj.Signal, cls);
                    testCase.verifyEmpty(E.Gain, cls);
                    testCase.verifyEmpty(E.Phase, cls);
                    testCase.verifyEmpty(E.Background, cls);
                    testCase.verifyEqual(obj.embedded_signal(), double(obj.Signal), cls);
                    testCase.verifyEqual(obj.audition_signal(), double(obj.Signal), cls);
                end
            end
        end

        function backgroundDoesNotChangeTheSignal(testCase)
            % Signal stays the stimulus alone: the same tone with and without
            % a background is the same waveform.
            args = {'Fs', testCase.Fs, 'ApplyCalibration', false, ...
                    'Frequency', 4000, 'Duration', 0.02};
            a = stimgen.Tone(args{:});
            b = stimgen.Tone(args{:}, 'Background', "Noise", 'BackgroundLevel', 40);
            a.update_signal();
            b.update_signal();
            testCase.verifyEqual(b.Signal, a.Signal);
            testCase.verifyEqual(b.N, a.N);
        end

        function structWithoutBackgroundFieldsLoadsAsNone(testCase)
            % A bank saved before the background existed names none of its
            % properties; restoring it must give a stimulus with no background.
            t = stimgen.Tone('Fs', testCase.Fs, 'ApplyCalibration', false, 'Frequency', 2000);
            S = t.toStruct();
            bg = stimgen.StimType.BackgroundProperties;
            testCase.assertTrue(all(isfield(S, cellstr(bg))));
            S = rmfield(S, cellstr(bg));
            S.UserProperties = S.UserProperties(~ismember(S.UserProperties, bg));

            t2 = stimgen.StimType.fromStruct(S);
            testCase.verifyEqual(t2.Background, "None");
            testCase.verifyEqual(t2.Frequency, 2000);
            testCase.verifyEmpty(t2.get_background());
        end

        function backgroundRoundTripsThroughStruct(testCase)
            t = stimgen.Tone('Fs', testCase.Fs, 'ApplyCalibration', false, ...
                'Background', "Noise", 'BackgroundLevel', [40 50], ...
                'BackgroundHighPass', 2000, 'BackgroundLowPass', 8000, ...
                'BackgroundLoopDuration', 2, 'BackgroundSeed', 7);
            t2 = stimgen.StimType.fromStruct(t.toStruct());
            testCase.verifyEqual(t2.Background, "Noise");
            testCase.verifyEqual(t2.BackgroundLevel, [40 50]);
            testCase.verifyEqual(t2.BackgroundHighPass, 2000);
            testCase.verifyEqual(t2.BackgroundLowPass, 8000);
            testCase.verifyEqual(t2.BackgroundLoopDuration, 2);
            testCase.verifyEqual(t2.BackgroundSeed, 7);
            testCase.verifyEqual(t2.get_variant_info().NumCombinations, 2);
        end

        function noiseLoopHasItsLengthLevelAndBand(testCase)
            cal   = flat_calibration_();
            level = 60;
            fs    = testCase.Fs;
            t = in_noise_(cal, fs, level, 11);
            B = t.get_background();

            testCase.verifyEqual(B.Type, "Noise");
            testCase.verifyTrue(B.Calibrated);
            testCase.verifyEqual(B.Fs, fs);
            testCase.verifyEqual(numel(B.Waveform), fs);        % 1 s loop
            testCase.verifyEqual(B.LoopDuration, 1);
            testCase.verifyEqual(B.Seed, 11);

            % The level a stimgen.Noise at this SoundLevel has: the rms of the
            % sine whose peak is the table's voltage.
            v = cal.compute_adjusted_voltage("filter", NaN, level);
            want = v * stimgen.calibration.Engine.LutRmsPerVolt;
            testCase.verifyEqual(rms_(B.Waveform), want, 'RelTol', 1e-9);
            testCase.verifyEqual(B.Rms, want, 'RelTol', 1e-9);

            nz = stimgen.Noise('Fs', fs, 'Duration', 1, 'SoundLevel', level, ...
                'HighPass', 2000, 'LowPass', 8000, 'ApplyWindow', false);
            nz.Calibration = cal;
            nz.update_signal();
            testCase.verifyEqual(rms_(B.Waveform), rms_(nz.Signal), 'RelTol', 1e-9);

            % Band-limited: nearly all of the loop's power lies in the band.
            % The loop is exactly periodic, so its FFT bins are exact.
            P = abs(fft(B.Waveform)) .^ 2;
            f = (0:numel(P)-1) * fs / numel(P);
            half  = f <= fs / 2;
            inBand = half & f >= 2000 & f <= 8000;
            testCase.verifyGreaterThan(sum(P(inBand)) / sum(P(half)), 0.97);
        end

        function noiseLoopJoinsWithoutAStep(testCase)
            % The last sample of a lap is followed by the sample the noise
            % itself continued with, so the step across the seam is an
            % ordinary sample-to-sample step of the band, and the cross-faded
            % head is at the level of the rest.
            t = in_noise_(flat_calibration_(), testCase.Fs, 60, 12);
            B = t.get_background();
            y = B.Waveform;
            seam = abs(y(1) - y(end));
            testCase.verifyLessThanOrEqual(seam, max(abs(diff(y))));

            nx = round(B.Crossfade * B.Fs);
            testCase.verifyGreaterThan(nx, 0);
            testCase.verifyLessThan(abs(20*log10(rms_(y(1:nx)) / rms_(y))), 1.5);
        end

        function seedFixesTheNoiseAndLeavesTheGlobalStreamAlone(testCase)
            cal = flat_calibration_();
            fs  = testCase.Fs;

            before = rng;
            first  = in_noise_(cal, fs, 60, 21).get_background();
            testCase.verifyEqual(rng, before, ...
                'Building a background drew from or reseeded the global stream.');

            other = in_noise_(cal, fs, 60, 22).get_background();
            testCase.verifyNotEqual(other.Key, first.Key);
            testCase.verifyNotEqual(other.Waveform, first.Waveform);

            % Push the first loop out of background_source's memo, so asking
            % for it again regenerates it from the seed.
            for s = 23:26
                in_noise_(cal, fs, 60, s).get_background();
            end
            again = in_noise_(cal, fs, 60, 21).get_background();
            testCase.verifyEqual(again.Key, first.Key);
            testCase.verifyEqual(again.Waveform, first.Waveform);
        end

        function toneBackgroundIsTheTablesVoltage(testCase)
            cal = flat_calibration_();
            c = stimgen.ClickTrain('Fs', testCase.Fs, 'Duration', 0.05, ...
                'Background', "Tone", 'BackgroundFrequency', 4000, 'BackgroundLevel', 55);
            c.Calibration = cal;
            B = c.get_background();

            testCase.verifyEqual(B.Type, "Tone");
            testCase.verifyEmpty(B.Waveform);
            testCase.verifyEqual(B.Frequency, 4000);
            testCase.verifyEqual(B.Amplitude, ...
                cal.compute_adjusted_voltage("tone", 4000, 55), 'RelTol', 1e-12);
            testCase.verifyEqual(B.Rms, B.Amplitude / sqrt(2), 'RelTol', 1e-12);
            testCase.verifyTrue(B.Calibrated);

            % Without a calibration it is a unit sine, and says so.
            u = stimgen.ClickTrain('Fs', testCase.Fs, 'Duration', 0.05, ...
                'ApplyCalibration', false, 'Background', "Tone");
            Bu = u.get_background();
            testCase.verifyEqual(Bu.Amplitude, 1, 'AbsTol', 1e-12);
            testCase.verifyFalse(Bu.Calibrated);
        end

        function keyIsSharedExactlyWhenTheBackgroundIs(testCase)
            fs = testCase.Fs;
            bg = {'Background', "Noise", 'BackgroundLevel', 45, ...
                  'BackgroundHighPass', 2000, 'BackgroundLowPass', 8000, ...
                  'BackgroundLoopDuration', 1, 'BackgroundSeed', 3};
            a = stimgen.Tone('Fs', fs, 'ApplyCalibration', false, 'Frequency', 2000, bg{:});
            b = stimgen.Tone('Fs', fs, 'ApplyCalibration', false, 'Frequency', 8000, ...
                'SoundLevel', 30, bg{:});
            testCase.verifyEqual(a.get_background().Key, b.get_background().Key);

            % A vectorized property of the STIMULUS does not change it ...
            a.VariantReselectOnUpdate = false;
            a.SoundLevel = [30 50 70];
            keys = strings(1, 3);
            for v = 1:3
                a.set_variant_index(v);
                keys(v) = a.get_background().Key;
            end
            testCase.verifyEqual(numel(unique(keys)), 1);

            % ... a vectorized property of the BACKGROUND does.
            b.VariantReselectOnUpdate = false;
            b.SoundLevel = 30;
            b.BackgroundLevel = [35 45];
            b.set_variant_index(1);
            k1 = b.get_background().Key;
            b.set_variant_index(2);
            k2 = b.get_background().Key;
            testCase.verifyNotEqual(k1, k2);
            testCase.verifyEqual(k2, keys(1));   % 45 dB: the background a has
        end

        function unusedBackgroundSettingIsNotAVariantAxis(testCase)
            t = stimgen.Tone('Fs', testCase.Fs, 'ApplyCalibration', false, ...
                'BackgroundLevel', [40 50 60], 'BackgroundFrequency', [1000 2000]);
            testCase.verifyEqual(t.get_variant_info().NumCombinations, 1, ...
                'Background settings counted with Background = "None".');

            t.Background = "Noise";      % uses the level, not the frequency
            info = t.get_variant_info();
            testCase.verifyEqual(info.NumCombinations, 3);
            testCase.verifyEqual(info.PropertyNames, "BackgroundLevel");

            t.Background = "Tone";       % uses both
            testCase.verifyEqual(t.get_variant_info().NumCombinations, 6);

            t.Background = "None";
            testCase.verifyEqual(t.get_variant_info().NumCombinations, 1);
        end

        function embeddedSignalIsBackgroundPlusStimulus(testCase)
            fs = testCase.Fs;
            t = stimgen.Tone('Fs', fs, 'ApplyCalibration', false, 'Frequency', 4000, ...
                'Duration', 0.02, 'Background', "Noise", 'BackgroundHighPass', 2000, ...
                'BackgroundLowPass', 8000, 'BackgroundLoopDuration', 1, 'BackgroundSeed', 5);
            t.update_signal();
            B = t.get_background();

            % Pads long enough that the render runs past the end of the loop.
            pre = 0.6;  post = 0.7;
            [y, tt] = t.embedded_signal(pre, post);
            nPre = round(pre * fs);
            n    = numel(t.Signal);
            N    = nPre + n + round(post * fs);
            testCase.assertEqual(numel(y), N);
            testCase.verifyGreaterThan(N, numel(B.Waveform));
            testCase.verifyEqual(tt(nPre + 1), 0);

            want = B.Waveform(mod(0:N-1, numel(B.Waveform)) + 1);
            want(nPre + (1:n)) = want(nPre + (1:n)) + t.Signal;
            testCase.verifyEqual(y, want, 'AbsTol', 1e-12);

            % The same stimulus on a tone.
            t.Background = "Tone";
            t.BackgroundFrequency = 1000;
            B = t.get_background();
            y = t.embedded_signal(pre, post);
            want = B.Amplitude .* sin(2*pi * 1000 * (0:N-1) / fs);
            want(nPre + (1:n)) = want(nPre + (1:n)) + t.Signal;
            testCase.verifyEqual(y, want, 'AbsTol', 1e-9);
        end

        function amplitudeModulationIsItsClosedForm(testCase)
            fs = testCase.Fs;
            am = stimgen.BackgroundAM('Fs', fs, 'ApplyCalibration', false, ...
                'AMRate', 10, 'AMDepth', 0.5, 'Duration', 0.5, 'ApplyWindow', false, ...
                'BackgroundHighPass', 2000, 'BackgroundLowPass', 8000);
            am.update_signal();
            E = am.get_embedding();
            tt = (0:round(0.5 * fs) - 1) / fs;

            testCase.verifyEqual(E.Mode, "modulate");
            testCase.verifyEqual(numel(E.Signal), numel(tt));
            testCase.verifyFalse(any(E.Signal));
            testCase.verifyEmpty(E.Phase);
            testCase.verifyEqual(E.Gain, 1 + 0.5 * sin(2*pi*10*tt), 'AbsTol', 1e-12);
            testCase.verifyEqual(E.Gain, am.Gain);

            % Gated, the modulation is ramped and the carrier is not: the
            % envelope is exactly 1 at the first sample whatever the phase,
            % and never leaves [1 - depth, 1 + depth].
            am.OnsetPhase = 90;
            am.WindowDuration = 0.02;
            am.ApplyWindow = true;
            am.update_signal();
            g = am.Gain;
            testCase.verifyEqual(g(1), 1, 'AbsTol', 1e-12);
            testCase.verifyLessThan(abs(g(end) - 1), 0.01);
            testCase.verifyLessThanOrEqual(max(g), 1.5 + 1e-12);
            testCase.verifyGreaterThanOrEqual(min(g), 0.5 - 1e-12);
            testCase.verifyEqual(g(round(numel(g)/2)), ...
                1 + 0.5 * sin(2*pi*10*tt(round(numel(g)/2)) + pi/2), 'AbsTol', 1e-12);
        end

        function gapIsOneMinusTheGate(testCase)
            fs = testCase.Fs;
            gap = stimgen.BackgroundGap('Fs', fs, 'ApplyCalibration', false, ...
                'Duration', 0.02, 'WindowDuration', 0.004, ...
                'BackgroundHighPass', 2000, 'BackgroundLowPass', 8000);
            gap.update_signal();
            E = gap.get_embedding();
            g = E.Gain;

            testCase.verifyEqual(E.Mode, "modulate");
            testCase.verifyEmpty(E.Phase);
            testCase.verifyEqual(numel(g), round(0.02 * fs));
            testCase.verifyEqual(g(1), 1, 'AbsTol', 1e-12);      % continuous with the background
            testCase.verifyEqual(g(round(numel(g)/2)), 0, 'AbsTol', 1e-12);   % silence in the middle
            testCase.verifyGreaterThanOrEqual(min(g), -1e-12);
            % 2 ms falling, 2 ms rising, silent between.
            nRamp = round(0.002 * fs);
            testCase.verifyEqual(g(nRamp + 1 : end - nRamp), ...
                zeros(1, numel(g) - 2 * nRamp), 'AbsTol', 1e-12);
            testCase.verifyTrue(all(diff(g(1:nRamp)) <= 1e-12));

            % The stand-alone waveform is the background times that gain.
            testCase.verifyEqual(max(abs(gap.Signal(nRamp + 1 : end - nRamp))), 0, 'AbsTol', 1e-12);

            % A shallower gap is a level decrement.
            gap.GapDepth = 0.5;
            gap.update_signal();
            testCase.verifyEqual(gap.Gain(round(numel(g)/2)), 0.5, 'AbsTol', 1e-12);
        end

        function frequencyModulationIsAPhaseOfTheTone(testCase)
            fs = testCase.Fs;
            fm = stimgen.BackgroundFM('Fs', fs, 'ApplyCalibration', false, ...
                'BackgroundFrequency', 4000, 'FMRate', 10, 'FMDeviation', 100, ...
                'Duration', 0.5, 'ApplyWindow', false);
            fm.update_signal();
            E  = fm.get_embedding();
            tt = (0:round(0.5 * fs) - 1) / fs;

            testCase.verifyEqual(E.Mode, "modulate");
            testCase.verifyEmpty(E.Gain);
            testCase.verifyFalse(any(E.Signal));
            testCase.verifyEqual(E.Background.Type, "Tone");
            testCase.verifyEqual(E.Phase(1), 0);

            % The phase's rate of change is the frequency deviation.
            df = 100 * sin(2*pi*10*tt);
            testCase.verifyEqual(diff(E.Phase) * fs / (2*pi), df(1:end-1), 'AbsTol', 1e-9);

            % Stand-alone: a unit tone (no calibration) with that phase, at
            % constant amplitude.
            testCase.verifyEqual(fm.Signal, sin(2*pi*4000*tt + E.Phase), 'AbsTol', 1e-9);
            testCase.verifyEqual(fm.level_offset_db(), 0);

            % In its background the tone is continuous before, through and
            % after the modulation: no sample-to-sample step exceeds what the
            % highest instantaneous frequency allows.
            y = fm.embedded_signal(0.05, 0.05);
            testCase.verifyLessThanOrEqual(max(abs(diff(y))), 2*pi*(4000 + 100)/fs + 1e-9);
        end

        function frequencyModulationRefusesNoise(testCase)
            % Constructed with the wrong background (construction generates
            % nothing), then asked to generate.
            fm = stimgen.BackgroundFM('Fs', testCase.Fs, 'ApplyCalibration', false, ...
                'Background', "Noise");
            testCase.verifyError(@() fm.update_signal(), ...
                'stimgen:BackgroundFM:NeedsToneBackground');
            testCase.verifyEmpty(fm.Signal);

            am = stimgen.BackgroundAM('Fs', testCase.Fs, 'ApplyCalibration', false, ...
                'Background', "None");
            testCase.verifyError(@() am.update_signal(), ...
                'stimgen:BackgroundModulation:NoBackground');
            testCase.verifyEmpty(am.Signal);
        end

        function modulationLevelIsCarrierReferenced(testCase)
            % SoundLevel is the steady background's level. A full-depth AM
            % epoch is louder than that by 10*log10(1.5) = 1.76 dB, and a
            % level check is told so rather than calling it an error.
            cal   = flat_calibration_();
            level = 60;
            fs    = testCase.Fs;

            % On a tone the arithmetic is exact: 1 kHz and 10 Hz for 1 s are
            % whole cycles of both.
            am = stimgen.BackgroundAM('Fs', fs, 'SoundLevel', level, 'Duration', 1, ...
                'AMRate', 10, 'AMDepth', 1, 'ApplyWindow', false, ...
                'Background', "Tone", 'BackgroundFrequency', 1000);
            am.Calibration = cal;
            am.update_signal();

            v = cal.compute_adjusted_voltage("tone", 1000, level);
            testCase.verifyEqual(am.get_background().Amplitude, v, 'RelTol', 1e-12);
            testCase.verifyEqual(am.level_offset_db(), 10*log10(1.5), 'AbsTol', 1e-6);
            testCase.verifyEqual(rms_(am.Signal), v / sqrt(2) * sqrt(1.5), 'RelTol', 1e-6);

            req = stimgen.util.level_request(am);
            testCase.verifyEqual(req.mode, "rms");
            testCase.verifyEqual(req.level_db, level);
            testCase.verifyEqual(req.expected_offset_db, 10*log10(1.5), 'AbsTol', 1e-6);
            m = stimgen.util.level_as_calibrated(mic_(am.Signal), fs, req, 0.05);
            testCase.verifyEqual(m.level_db, level + 10*log10(1.5), 'AbsTol', 1e-3);
            testCase.verifyLessThan(abs(m.error_db), 1e-3);

            % On noise the same holds to within the noise's own fluctuation.
            amn = stimgen.BackgroundAM('Fs', fs, 'SoundLevel', level, 'Duration', 1, ...
                'AMRate', 10, 'AMDepth', 1, 'ApplyWindow', false, ...
                'BackgroundHighPass', 2000, 'BackgroundLowPass', 8000);
            amn.Calibration = cal;
            amn.update_signal();
            mn = stimgen.util.level_as_calibrated(mic_(amn.Signal), fs, ...
                stimgen.util.level_request(amn), 0.05);
            testCase.verifyLessThan(abs(mn.error_db), 0.6);

            % Every other stimulus expects no offset, and a request that
            % predates the field is read as none.
            tone = stimgen.Tone('Fs', fs, 'SoundLevel', level, 'Duration', 1, ...
                'ApplyWindow', false);
            tone.Calibration = cal;
            tone.update_signal();
            testCase.verifyEqual(stimgen.util.level_request(tone).expected_offset_db, 0);
            old = rmfield(req, 'expected_offset_db');
            mo  = stimgen.util.level_as_calibrated(mic_(am.Signal), fs, old, 0.05);
            testCase.verifyEqual(mo.error_db, 10*log10(1.5), 'AbsTol', 1e-3);
        end

        function panelRowsFollowTheBackgroundType(testCase)
            t = stimgen.Tone('Fs', testCase.Fs, 'ApplyCalibration', false);
            noiseRows = ["BackgroundLevel","BackgroundHighPass","BackgroundLowPass", ...
                         "BackgroundLoopDuration","BackgroundSeed"];
            toneRows  = ["BackgroundLevel","BackgroundFrequency"];
            all_ = unique([noiseRows, toneRows]);

            m = t.get_prop_meta();
            testCase.verifyTrue(isfield(m, 'Background'));
            testCase.verifyFalse(any(isfield(m, cellstr(all_))));
            testCase.verifyEqual(string(m.Background.group), "Background");

            t.Background = "Noise";
            m = t.get_prop_meta();
            testCase.verifyTrue(all(isfield(m, cellstr(noiseRows))));
            testCase.verifyFalse(isfield(m, 'BackgroundFrequency'));
            % A time, stored in seconds and shown in ms like the rest.
            testCase.verifyEqual(stimgen.StimType.display_scale(m, 'BackgroundLoopDuration'), 1000);

            t.Background = "Tone";
            m = t.get_prop_meta();
            testCase.verifyTrue(all(isfield(m, cellstr(toneRows))));
            testCase.verifyFalse(any(isfield(m, cellstr(setdiff(noiseRows, toneRows)))));

            % The group reaches the panel: group_prop_meta emits only the
            % groups it knows.
            sections = stimgen.StimType.group_prop_meta(m);
            groups = string(cellfun(@(s) s{1}, sections, 'UniformOutput', false));
            testCase.verifyTrue(any(groups == "Background"));

            % A modulation has one level: the background's is Sound Level.
            am = stimgen.BackgroundAM('Fs', testCase.Fs, 'ApplyCalibration', false);
            m = am.get_prop_meta();
            testCase.verifyFalse(isfield(m, 'BackgroundLevel'));
            testCase.verifyTrue(isfield(m, 'BackgroundHighPass'));
            testCase.verifyFalse(any(string(m.Background.items) == "None"));
            fm = stimgen.BackgroundFM('Fs', testCase.Fs, 'ApplyCalibration', false);
            testCase.verifyEqual(string(fm.get_prop_meta().Background.items), "Tone");
        end

        function copyAtAnotherRateGetsABackgroundAtThatRate(testCase)
            % What a presenter does: copy, set its own rate, regenerate. The
            % copy carries none of the source's listeners, so nothing cached
            % on the source may be served for it.
            t = stimgen.Tone('Fs', testCase.Fs, 'ApplyCalibration', false, ...
                'Background', "Noise", 'BackgroundHighPass', 2000, ...
                'BackgroundLowPass', 8000, 'BackgroundLoopDuration', 1, 'BackgroundSeed', 9);
            t.update_signal();
            B = t.get_background();

            c = copy(t);
            c.Fs = 2 * testCase.Fs;
            c.update_signal();
            Bc = c.get_background();
            testCase.verifyEqual(Bc.Fs, 2 * testCase.Fs);
            testCase.verifyEqual(numel(Bc.Waveform), 2 * testCase.Fs);
            testCase.verifyNotEqual(Bc.Key, B.Key);

            testCase.verifyEqual(t.get_background().Key, B.Key);
            testCase.verifyEqual(numel(t.get_background().Waveform), testCase.Fs);
        end

        function auditionPutsTheStimulusInItsBackground(testCase)
            fs = testCase.Fs;
            gap = stimgen.BackgroundGap('Fs', fs, 'ApplyCalibration', false, ...
                'Duration', 0.02, 'BackgroundHighPass', 2000, 'BackgroundLowPass', 8000);
            gap.update_signal();
            [y, tt] = gap.audition_signal();
            testCase.verifyGreaterThan(numel(y), numel(gap.Signal));
            testCase.verifyEqual(y(1), 0, 'AbsTol', 1e-12);      % the preview's own ramp
            testCase.verifyEqual(tt(find(tt >= 0, 1)), 0);
            % Background before the gap, silence inside it.
            before = y(tt > -0.1 & tt < -0.01);
            inside = y(tt > 0.005 & tt < 0.015);
            testCase.verifyGreaterThan(rms_(before), 0);
            testCase.verifyEqual(max(abs(inside)), 0, 'AbsTol', 1e-12);
        end

        function recordingHasNoBackground(testCase)
            c = stimgen.CapturedSignal(0.1 * randn(1, 480), testCase.Fs);
            testCase.verifyFalse(any(ismember(stimgen.StimType.BackgroundProperties, ...
                c.UserProperties)));
            testCase.verifyEmpty(c.get_background());
            testCase.verifyFalse(isfield(c.get_prop_meta(), 'Background'));
            S = c.toStruct();
            testCase.verifyFalse(isfield(S, 'BackgroundLevel'));
        end

    end
end


% ====================================================================== %

function cal = flat_calibration_()
% Offline calibration whose tone (and swept sine) table is 1 V for 70 dB at
% every frequency, on a 50 mV/Pa microphone -- the table LevelConventionTest
% uses, so a lookup returns the same voltage at any frequency.
f = [125; 250; 500; 1000; 2000; 4000; 8000; 16000];
t = struct('frequency', f, ...
           'measurement', 0.05 * 20e-6 * 10^(70/20) * ones(size(f)), ...
           'spl_db', 70 * ones(size(f)), ...
           'voltage', ones(size(f)), ...
           'normative_db', 70);
calData = struct('tone', t, 'swept_sine', t, 'filter', [], 'filterGrpDelay', 0);
s = struct('version', 3, 'CalibrationData', calData, 'NormativeValue', 70, ...
           'MicSensitivity', 0.05, 'ReferenceFrequency', 1000, ...
           'ExcitationVoltage', 1);
cal = stimgen.StimCalibration.loadobj(s);
end


function t = in_noise_(cal, fs, level, seed)
% A calibrated tone embedded in a 1 s loop of 2-8 kHz noise at `level`.
t = stimgen.Tone('Fs', fs, 'Frequency', 4000, 'Duration', 0.02, ...
    'Background', "Noise", 'BackgroundLevel', level, ...
    'BackgroundHighPass', 2000, 'BackgroundLowPass', 8000, ...
    'BackgroundLoopDuration', 1, 'BackgroundSeed', seed);
t.Calibration = cal;
end


function y = mic_(x)
% What the flat table's rig returns for the drive x, in microphone volts.
% The table says a sine of 1 V PEAK measures 70 dB SPL (rms) on a 50 mV/Pa
% microphone, so the rig's gain from drive volts to microphone volts is that
% rms over the sine's rms, 1/sqrt(2).
k = 0.05 * 20e-6 * 10^(70/20);
y = x .* (k * sqrt(2));
end


function r = rms_(x)
r = sqrt(mean(x(:) .^ 2));
end
