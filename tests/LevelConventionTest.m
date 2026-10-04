classdef LevelConventionTest < matlab.unittest.TestCase
    % SoundLevel is an rms dB SPL for every continuous stimulus, whatever the
    % stimulus is normalized to before calibration scales it.
    %
    % A LUT voltage is the PEAK of the sine that produced the table's level:
    % calibrate_tones plays ExcitationVoltage .* (a unit-amplitude tone),
    % measures the rms that comes back, and solves for the drive that gives
    % NormativeValue. A tone scaled to that voltage (absmax normalization) has
    % an rms of V/sqrt(2). A stimulus normalized to rms = 1 and scaled to the
    % same V has an rms of V -- 3.01 dB more -- unless calibration carries
    % that sine's rms instead.
    %
    % Two kinds of check:
    %   - on a flat table, offline: every rms-normalized stimulus must carry
    %     the same electrical rms as a tone at the same SoundLevel, and the
    %     hardware-filter level reference must agree with the software path;
    %   - on the simulated rig (documentation/tools/SimRigAdapter), measured
    %     the way SpotCheck measures (level_request + level_as_calibrated):
    %     the same 1 kHz sine played as a Tone and as an rms-referenced
    %     SoundFile must both land on the requested level.
    %
    % Run from the repository root:
    %   addpath(pwd); results = runtests('tests');
    % See tests/README.md.

    properties (Constant)
        Fs = 48000
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'documentation', 'tools')));
        end
    end

    % ------------------------------------------------------------------ %
    methods (Test)

        function rmsNormalizedStimuliMatchATone(testCase)
            % Flat 1 V table at 70 dB, so every lookup returns the same V and
            % any difference in rms is the normalization alone.
            cal   = flat_calibration_();
            level = 64;
            fs    = testCase.Fs;
            v     = cal.compute_adjusted_voltage("tone", 1000, level);
            testCase.assertEqual(v, 10^((level - 70)/20), 'RelTol', 1e-12);

            % 1 kHz for 1 s at 48 kHz is a whole number of cycles, so the
            % sampled sine's rms is V/sqrt(2) to rounding.
            tone = make_(cal, 'stimgen.Tone', fs, level, 'Frequency', 1000);
            toneRms = rms_(tone.Signal);
            testCase.assertEqual(toneRms, v / sqrt(2), 'RelTol', 1e-9);

            cases = { ...
                'stimgen.Noise',          {'HighPass', 500, 'LowPass', 8000}; ...
                'stimgen.AMnoise',        {'HighPass', 500, 'LowPass', 8000}; ...
                'stimgen.AttackModNoise', {'HighPass', 500, 'LowPass', 8000}; ...
                'stimgen.TORC',           {}};
            for k = 1:size(cases, 1)
                args = cases{k, 2};
                s = make_(cal, cases{k, 1}, fs, level, args{:});
                r = rms_(s.Signal);
                fprintf('LEVELCHECK %-24s rms %.6f V, tone %.6f V, %+.3f dB\n', ...
                    cases{k, 1}, r, toneRms, 20*log10(r / toneRms));
                testCase.verifyEqual(r, toneRms, 'RelTol', 1e-9, ...
                    sprintf('%s at %g dB does not carry a tone''s rms', cases{k, 1}, level));
            end

            % Constant-envelope, absmax-normalized: already a sine's rms.
            fm = make_(cal, 'stimgen.FMtone', fs, level, ...
                'CarrierFrequency', 2000, 'ModulationFrequency', 10, 'ModulationDepth', 200);
            testCase.verifyEqual(rms_(fm.Signal), toneRms, 'RelTol', 1e-3);
        end

        function soundFileHonoursItsLevelReference(testCase)
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            fs  = testCase.Fs;
            ffn = write_sine_(tmp.Folder, fs, 1000, 1);
            cal   = flat_calibration_();
            level = 64;
            v     = cal.compute_adjusted_voltage("tone", 1000, level);

            % rms reference: the file's rms is placed where a tone's would be.
            s = sound_file_(cal, ffn, fs, level, "rms");
            r = rms_(s.Signal);
            fprintf('LEVELCHECK %-24s rms %.6f V, tone %.6f V, %+.3f dB\n', ...
                'stimgen.SoundFile (rms)', r, v/sqrt(2), 20*log10(r / (v/sqrt(2))));
            testCase.verifyEqual(r, v / sqrt(2), 'RelTol', 1e-9);

            % peak reference: the file's peak is placed where a tone's peak
            % is, which for a sine file is the same waveform as the Tone.
            p = sound_file_(cal, ffn, fs, level, "peak");
            testCase.verifyEqual(max(abs(p.Signal)), v, 'RelTol', 1e-9);
        end

        function filterLevelReferenceAgreesWithSoftware(testCase)
            % The hardware chain (source -> FIR -> gain) and apply_calibration
            % must put a white source at the same level. At NormativeValue,
            % the software path's rms is what scale * filteredRms has to be.
            cal = flat_calibration_();
            fs  = testCase.Fs;
            cal.Engine.design_filter("tone", SampleRate=fs, ShowResponse=false, ...
                NumCoefficients=129);
            n = make_(cal, 'stimgen.Noise', fs, 70, 'HighPass', 500, 'LowPass', 8000);
            r = cal.Engine.filter_level_reference(1);
            fprintf('LEVELCHECK filter_level_reference: scale*rms %.6f V, software %.6f V\n', ...
                r.scale * r.filteredRms, rms_(n.Signal));
            testCase.verifyEqual(r.scale * r.filteredRms, rms_(n.Signal), 'RelTol', 1e-9);
            testCase.verifyEqual(r.unityGainSpl, 70 - 20*log10(r.scale), 'AbsTol', 1e-9);
        end

        function spotCheckOnTheSimulatedRig(testCase)
            % The measurement row 2 of the review asked for, on the simulated
            % rig instead of a speaker: calibrate, then play the same 1 kHz
            % sine as a Tone (absmax) and as a SoundFile referenced to its
            % rms (and to its peak), and measure each the way SpotCheck does.
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            [rig, eng] = calibrated_rig_([500 707 1000 1414 2000]);
            fs  = rig.sample_rate();
            cal = stimgen.StimCalibration.loadobj(eng.to_struct());
            ffn = write_sine_(tmp.Folder, fs, 1000, 0.5);
            level = 65;

            tone = make_(cal, 'stimgen.Tone', fs, level, 'Frequency', 1000, 'Duration', 0.5);
            sRms = sound_file_(cal, ffn, fs, level, "rms");
            sPk  = sound_file_(cal, ffn, fs, level, "peak");

            stims = {tone, sRms, sPk};
            names = ["Tone", "SoundFile rms", "SoundFile peak"];
            for k = 1:numel(stims)
                m = measure_(rig, eng, stims{k});
                fprintf('LEVELCHECK sim rig %-15s mode %-8s %.2f %s, asked %g, error %+.2f dB\n', ...
                    names(k), m.mode, m.level_db, m.level_unit, level, m.error_db);
                testCase.verifyLessThan(abs(m.error_db), 0.3, ...
                    sprintf('%s measured %+.2f dB from its requested level', names(k), m.error_db));
            end
        end

        function equalizedNoiseLevelDiagnostic(testCase)
            % Diagnostic only: an equalized broadband noise on the simulated
            % rig, measured as SpotCheck would. Reports the level error; the
            % only assertion is that one was measured.
            [rig, eng] = calibrated_rig_(250 * 2.^(0:0.5:6));
            fs = rig.sample_rate();
            eng.design_filter("tone", SampleRate=fs, ShowResponse=false, ...
                NumCoefficients=257, SmoothingOctaves=1/6);
            cal = stimgen.StimCalibration.loadobj(eng.to_struct());
            bands = [500 8000; 250 16000; 1000 4000; 800 1250];
            for k = 1:size(bands, 1)
                n = make_(cal, 'stimgen.Noise', fs, 65, 'HighPass', bands(k,1), ...
                    'LowPass', bands(k,2), 'Duration', 1);
                m = measure_(rig, eng, n);
                fprintf('LEVELCHECK sim rig equalized Noise %5g-%5g Hz: %.2f dB SPL, asked 65, error %+.2f dB\n', ...
                    bands(k,1), bands(k,2), m.level_db, m.error_db);
                testCase.verifyTrue(isfinite(m.error_db));
            end
        end

    end
end


% ====================================================================== %

function cal = flat_calibration_()
% Offline calibration whose tone (and swept sine) table is 1 V for 70 dB at
% every frequency, on a 50 mV/Pa microphone.
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


function s = make_(cal, cls, fs, level, varargin)
% A calibrated stimulus, ungated so the whole record is at level, 1 s long
% unless the caller says otherwise.
s = feval(cls, 'Fs', fs, 'Duration', 1, 'SoundLevel', level, ...
    'ApplyWindow', false, varargin{:});
s.Calibration = cal;
s.ApplyCalibration = true;
s.update_signal();
end


function s = sound_file_(cal, ffn, fs, level, ref)
s = stimgen.SoundFile('Fs', fs, 'SoundLevel', level, 'ApplyWindow', false, ...
    'CalibrationMode', "Direct", 'AnchorFrequency', 1000, 'LevelReference', ref);
s.add_files(string(ffn));
s.Calibration = cal;
s.ApplyCalibration = true;
s.update_signal();
end


function ffn = write_sine_(folder, fs, f, dur)
ffn = fullfile(folder, sprintf('sine_%g.wav', f));
t = (0:round(dur * fs) - 1) / fs;
audiowrite(ffn, 0.5 * sin(2*pi*f*t), fs, 'BitsPerSample', 32);
end


function [rig, eng] = calibrated_rig_(freqs)
% The simulated rig with its microphone referenced and a tone table built.
rig = SimRigAdapter('CalibratorOn', true);
eng = stimgen.calibration.Engine(rig);
eng.calibrate_reference();
rig.CalibratorOn = false;
eng.set_configuration(NormativeValue=70);
eng.calibrate_tones(freqs, 2);
end


function m = measure_(rig, eng, stim)
% Play the stimulus with a silent tail and measure its steady middle, the
% way SpotCheck reads a record: level_request says how, level_as_calibrated
% does it.
fs = rig.sample_rate();
y  = [stim.Signal, zeros(1, round(0.1 * fs))];
r  = rig.play_and_record(y);
n  = numel(stim.Signal);
seg = r(round(0.1 * n) + 1 : round(0.9 * n));
m = stimgen.util.level_as_calibrated(seg, fs, stimgen.util.level_request(stim), ...
    eng.MicSensitivity);
end


function r = rms_(x)
r = sqrt(mean(x(:) .^ 2));
end
