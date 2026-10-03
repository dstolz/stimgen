classdef CalibrationEngineTest < matlab.unittest.TestCase
    % stimgen.calibration.Engine against a simulated rig: the reference step
    % recovers the microphone's sensitivity, and a calibration survives a
    % .esgc save/load.
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
