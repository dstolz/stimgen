classdef CalibrationEngineTest < matlab.unittest.TestCase
    % stimgen.calibration.Engine against a simulated rig: the reference step
    % recovers the microphone's sensitivity and marks it known, a calibration
    % survives a .esgc save/load, tone tables record the level they were
    % solved for (and restore stamps old ones), and a repeated sweep
    % frequency is dropped.
    %
    % The rig is documentation/tools/SimRigAdapter, a seeded synthetic
    % speaker + room + microphone (50 mV/Pa) whose record() returns the
    % acoustic calibrator's tone when CalibratorOn is set. Being seeded, it
    % gives the same samples on every run.
    %
    % Run from the repository root:
    %   addpath(pwd); results = runtests('tests');
    % See tests/README.md.

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

        function referenceRecoversMicSensitivity(testCase)
            % A 94 dB SPL calibrator on a 50 mV/Pa microphone. The engine
            % reads the tone's rms with a flat-top window, whose scalloping
            % is a few thousandths of a dB; the floor under the tone is ~60
            % dB down. 0.2 % is 0.017 dB.
            rig = SimRigAdapter('CalibratorOn', true);
            eng = stimgen.calibration.Engine(rig);
            eng.calibrate_reference();
            testCase.verifyEqual(eng.MicSensitivity, 0.050, 'RelTol', 2e-3);
            testCase.verifyEqual(eng.MicSensitivity, rig.MicVPerPa, 'RelTol', 2e-3);
        end

        function referenceDoesNotDependOnCalibratorLevel(testCase)
            % ReferenceLevel enters only the sensitivity: a 114 dB calibrator
            % declared as 114 dB yields the same V/Pa as a 94 dB one.
            rig = SimRigAdapter('CalibratorOn', true, 'CalibratorLevel', 114);
            eng = stimgen.calibration.Engine(rig);
            eng.set_configuration(ReferenceLevel=114);
            eng.calibrate_reference();
            testCase.verifyEqual(eng.MicSensitivity, 0.050, 'RelTol', 2e-3);
        end

        function referenceRefusesASilentRecord(testCase)
            % No calibrator: the record is the room alone, and the step must
            % refuse rather than set a sensitivity from noise.
            rig = SimRigAdapter('CalibratorOn', false);
            eng = stimgen.calibration.Engine(rig);
            before = eng.MicSensitivity;
            testCase.verifyError(@() eng.calibrate_reference(), ...
                'stimgen:calibration:Engine:noReferenceTone');
            testCase.verifyEqual(eng.MicSensitivity, before);
        end

        function saveAndLoadRoundTrip(testCase)
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);

            rig = SimRigAdapter('CalibratorOn', true);
            eng = stimgen.calibration.Engine(rig);
            eng.set_configuration(Notes="simulated rig", AdcGain=6, DacAttenuation=-3);
            eng.calibrate_reference();

            % A calibration has to hold data before it can be saved; the
            % background floor is the cheapest measurement that stores some.
            rig.CalibratorOn = false;
            bg = eng.measure_background(0.5, 2);
            testCase.assertTrue(eng.IsCalibrated);

            ffn = eng.save(fullfile(tmp.Folder, 'sim.esgc'));
            testCase.verifyTrue(isfile(ffn));

            loaded = stimgen.calibration.Engine.load(ffn);
            testCase.verifyClass(loaded, 'stimgen.calibration.Engine');
            testCase.verifyEmpty(loaded.Adapter);

            testCase.verifyEqual(loaded.MicSensitivity, eng.MicSensitivity);
            testCase.verifyEqual(loaded.Notes, "simulated rig");
            testCase.verifyEqual(loaded.AdcGain, 6);
            testCase.verifyEqual(loaded.DacAttenuation, -3);
            testCase.verifyEqual(loaded.CalibrationData.background.spl_db, bg.spl_db);

            % The whole persistent state, field by field.
            a = eng.to_struct();
            b = loaded.to_struct();
            testCase.verifyEqual(sort(fieldnames(b)), sort(fieldnames(a)));
            fn = fieldnames(a);
            for k = 1:numel(fn)
                testCase.verifyTrue(isequaln(a.(fn{k}), b.(fn{k})), ...
                    sprintf('field "%s" did not survive save/load', fn{k}));
            end
        end

        function micSensitivityKnownOnlyOnceMeasured(testCase)
            % A fresh engine's 1 V/Pa is a placeholder, not a scale, and
            % known_mic_sensitivity() says so with NaN. Echoing that value
            % back through set_configuration must not promote it.
            rig = SimRigAdapter('CalibratorOn', true);
            eng = stimgen.calibration.Engine(rig);
            testCase.verifyFalse(eng.MicSensitivityKnown);
            testCase.verifyTrue(isnan(eng.known_mic_sensitivity()));
            eng.set_configuration(MicSensitivity=eng.MicSensitivity);
            testCase.verifyFalse(eng.MicSensitivityKnown);

            eng.calibrate_reference();
            testCase.verifyTrue(eng.MicSensitivityKnown);
            testCase.verifyEqual(eng.known_mic_sensitivity(), eng.MicSensitivity);
        end

        function micSensitivityKnownSurvivesSaveLoad(testCase)
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);

            % Measured: loads as known, with the same value.
            rig = SimRigAdapter('CalibratorOn', true);
            eng = stimgen.calibration.Engine(rig);
            eng.calibrate_reference();
            rig.CalibratorOn = false;
            eng.measure_background(0.5, 1);   % something to save
            loaded = stimgen.calibration.Engine.load( ...
                eng.save(fullfile(tmp.Folder, 'known.esgc')));
            testCase.verifyTrue(loaded.MicSensitivityKnown);
            testCase.verifyEqual(loaded.known_mic_sensitivity(), eng.MicSensitivity);

            % Never measured: loads as unknown, not as a 1 V/Pa scale.
            eng2 = stimgen.calibration.Engine(SimRigAdapter());
            eng2.measure_background(0.5, 1);
            loaded2 = stimgen.calibration.Engine.load( ...
                eng2.save(fullfile(tmp.Folder, 'unknown.esgc')));
            testCase.verifyFalse(loaded2.MicSensitivityKnown);
            testCase.verifyTrue(isnan(loaded2.known_mic_sensitivity()));
        end

        function toneTableRecordsItsNormativeLevel(testCase)
            % Each committed tone table records the NormativeValue it was
            % solved for, and a lookup scales from that record: moving
            % NormativeValue afterwards is a setting for the next sweep and
            % must not shift the drive of the table already measured.
            rig = SimRigAdapter();
            eng = stimgen.calibration.Engine(rig);
            freqs = [500 1000 2000 4000];

            eng.set_configuration(NormativeValue=70);
            eng.calibrate_tones(freqs, 1);
            t = eng.CalibrationData.tone;
            testCase.verifyEqual(t.normative_db, 70);
            testCase.verifyEqual(t.frequency, freqs(:));

            vBefore = eng.compute_adjusted_voltage("tone", 1500, 60);
            eng.set_configuration(NormativeValue=90);
            vAfter = eng.compute_adjusted_voltage("tone", 1500, 60);
            testCase.verifyEqual(vAfter, vBefore);
            testCase.verifyEqual(eng.CalibrationData.tone.normative_db, 70);
            % Scaled from the table's 70 dB, not the live 90 dB.
            testCase.verifyEqual(vAfter, ...
                makima(t.frequency, t.voltage, 1500) * 10^((60 - 70)/20), ...
                'RelTol', 1e-12);

            % The next sweep is the one the new setting applies to.
            eng.calibrate_tones(freqs, 1);
            testCase.verifyEqual(eng.CalibrationData.tone.normative_db, 90);
        end

        function restoreStampsUnversionedTables(testCase)
            % A struct from before tables recorded normative_db (no version,
            % no field) gets each table stamped with the struct's own
            % NormativeValue; a table that already records one is left alone.
            tone  = struct('frequency', [500; 1000; 2000], ...
                           'measurement', [0.03; 0.03; 0.03], ...
                           'spl_db', [64; 64; 64], ...
                           'voltage', [1.2; 0.8; 0.6]);
            click = struct('duration', [50e-6; 100e-6; 200e-6], ...
                           'measurement', [0.1; 0.2; 0.3], ...
                           'spl_db', [70; 76; 80], ...
                           'voltage', [2; 1; 0.5]);
            swept = tone;
            swept.normative_db = 50;
            cd = struct('tone', tone, 'click', click, 'swept_sine', swept, ...
                        'filter', [], 'filterGrpDelay', 0);
            s = struct('CalibrationData', cd, 'NormativeValue', 65);
            testCase.assertFalse(isfield(s, 'version'));

            eng = stimgen.calibration.Engine();
            eng.restore(s);
            testCase.verifyEqual(eng.NormativeValue, 65);
            testCase.verifyEqual(eng.CalibrationData.tone.normative_db, 65);
            testCase.verifyEqual(eng.CalibrationData.click.normative_db, 65);
            testCase.verifyEqual(eng.CalibrationData.swept_sine.normative_db, 50);

            % The stamp, not the live setting, is what a lookup scales from:
            % at a measured frequency and the stamped level the table's own
            % voltage comes back.
            eng.set_configuration(NormativeValue=80);
            testCase.verifyEqual(eng.compute_adjusted_voltage("tone", 1000, 65), 0.8, ...
                'RelTol', 1e-12);
        end

        function duplicateToneFrequencyIsDropped(testCase)
            % A repeated frequency would leave makima with coincident
            % abscissae and a table nothing can be looked up in. It is
            % dropped before the sweep, and the drop is logged (through
            % vprintf, not warning(), so it is captured with a log sink).
            previous = stimgen.util.logSink();
            testCase.addTeardown(@() stimgen.util.logSink(previous));
            records = containers.Map('KeyType', 'double', 'ValueType', 'any');
            stimgen.util.logSink(stimgen.FcnLogSink( ...
                @(level, red, msg, args) append_record_(records, level, red, msg, args), ...
                @(level) level <= 0));

            eng = stimgen.calibration.Engine(SimRigAdapter());
            eng.calibrate_tones([1000 500 1000 2000], 1);

            t = eng.CalibrationData.tone;
            testCase.verifyEqual(t.frequency, [500; 1000; 2000]);
            testCase.verifyEqual(numel(unique(t.frequency)), numel(t.frequency));
            testCase.verifyEqual(numel(t.voltage), 3);
            % A lookup between the points works, which is the point.
            testCase.verifyTrue(isfinite(eng.compute_adjusted_voltage("tone", 750, 60)));

            found = false;
            for k = 1:double(records.Count)
                r = records(k);
                if (ischar(r.msg) || isstring(r.msg)) ...
                        && contains(string(r.msg), "duplicate frequency")
                    found = true;
                    testCase.verifyEqual(r.args, {1, 3});
                end
            end
            testCase.verifyTrue(found, 'the dropped duplicate was not logged');
        end

        function loadRejectsOtherExtensions(testCase)
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            ffn = fullfile(tmp.Folder, 'old.sgc');
            s = struct('version', 2); %#ok<NASGU>
            save(ffn, '-struct', 's', '-mat');
            testCase.verifyError(@() stimgen.calibration.Engine.load(ffn), ...
                'stimgen:calibration:Engine:wrongFormat');
        end

    end
end


% ====================================================================== %

function append_record_(records, level, red, msg, args)
% Log sink callback: one record per message, keyed in arrival order.
% records is a containers.Map, a handle, so the caller sees the addition.
records(records.Count + 1) = struct('level', level, 'red', red, 'msg', {msg}, 'args', {args}); %#ok<NASGU>
end
