classdef GuiSmokeTest < matlab.unittest.TestCase
    % Build the two GUIs offline and drive the paths that need no audio
    % device, no hardware and no modal dialog: StimPlayer with one bank item
    % of every stimulus class (selection, combination stepping, duplicate,
    % the combination viewer, the inspector, save/load of a bank), and
    % CalibrationGui on an offline engine holding every table and on a live
    % one with the simulated rig attached.
    %
    % A smoke test: it catches a method that no longer resolves, a callback
    % that errors on construction, a refresh path that fails on real data --
    % what a refactor of these classes is most likely to break -- not what
    % the windows look like. Where no figure can be created (a runner with
    % no display), each test says so in the log and returns.
    %
    % Run from the repository root:
    %   addpath(pwd); results = runtests('tests');
    % See tests/README.md.

    properties
        GuiOk (1,1) logical = false
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, 'documentation', 'tools')));
        end

        function probeDisplay(testCase)
            try
                f = uifigure('Visible', 'off');
                delete(f);
                testCase.GuiOk = true;
            catch ME
                fprintf('GUISMOKE no uifigure on this runner: %s\n', ME.message);
            end
        end
    end

    methods (TestMethodSetup)
        function closeStrayFigures(testCase)
            testCase.addTeardown(@() delete(findall(groot, 'Type', 'figure')));
        end
    end

    % ------------------------------------------------------------------ %
    methods (Test)

        function stimPlayerOffline(testCase)
            if ~testCase.GuiOk
                fprintf('GUISMOKE skipped stimPlayerOffline\n');
                return
            end
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);

            p = stimgen.StimPlayer();
            testCase.addTeardown(@() delete_if_valid_(p));
            p.Fs = 48000;

            % One of every class the type dropdown offers.
            classes = cellstr(stimgen.StimType.list());
            for k = 1:numel(classes)
                s = feval(['stimgen.' classes{k}], 'Fs', 48000, 'ApplyCalibration', false);
                p.open_stim(s, Name=string(classes{k}));
            end
            % And a vectorized one to step through.
            p.open_stim(stimgen.Tone('Fs', 48000, 'Duration', 0.05, ...
                'ApplyCalibration', false, 'Frequency', [1000 2000 4000]), Name="tones");
            n = numel(p.StimPlayObjs);
            testCase.verifyEqual(n, numel(classes) + 1);

            % Visit every bank item, as a click on the list would.
            lb = findall(groot, 'Tag', 'BankList');
            testCase.assertNotEmpty(lb);
            lb = lb(1);
            for k = 1:n
                lb.Value = k;
                p.on_bank_selection_changed(lb, []);
            end

            % The vectorized item is selected last: step it both ways.
            p.step_combination(1);
            p.step_combination(1);
            p.step_combination(-1);
            info = p.StimPlayObjs(n).CurrentStimObj.get_variant_info();
            testCase.verifyEqual(info.NumCombinations, 3);

            p.duplicate_stim();
            testCase.verifyEqual(numel(p.StimPlayObjs), n + 1);

            v = p.show_all_combinations();
            testCase.verifyClass(v, 'stimgen.CombinationViewer');
            delete(v);

            p.open_stim_inspector();

            ffn = fullfile(tmp.Folder, 'smoke.spl');
            p.save_bank(ffn);
            testCase.verifyTrue(isfile(ffn));
            testCase.verifyEqual(p.BankFile, string(ffn));
            p.load_bank(ffn);
            testCase.verifyEqual(numel(p.StimPlayObjs), n + 1);

            delete(p);
            testCase.verifyFalse(isvalid(p));
        end

        function calibrationGuiOfflineWithEveryTable(testCase)
            if ~testCase.GuiOk
                fprintf('GUISMOKE skipped calibrationGuiOfflineWithEveryTable\n');
                return
            end
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);

            rig = SimRigAdapter('CalibratorOn', true);
            eng = stimgen.calibration.Engine(rig);
            eng.calibrate_reference();
            rig.CalibratorOn = false;
            eng.measure_background(0.2, 1);
            eng.calibrate_tones([500 1000 2000 4000], 1);
            eng.calibrate_clicks([1e-4 2e-4 4e-4], 1);
            eng.design_filter("tone", SampleRate=rig.sample_rate(), ...
                ShowResponse=false, NumCoefficients=65);
            ffn = eng.save(fullfile(tmp.Folder, 'smoke.esgc'));
            offline = stimgen.calibration.Engine.load(ffn);

            g = stimgen.calibration.CalibrationGui(offline);
            testCase.addTeardown(@() delete_if_valid_(g));
            g.show();
            testCase.verifyClass(g.Monitor, 'stimgen.calibration.LiveMonitor');
            delete(g);
            testCase.verifyFalse(isvalid(g));
        end

        function calibrationGuiLive(testCase)
            if ~testCase.GuiOk
                fprintf('GUISMOKE skipped calibrationGuiLive\n');
                return
            end
            eng = stimgen.calibration.Engine(SimRigAdapter());
            g = stimgen.calibration.CalibrationGui(eng);
            testCase.addTeardown(@() delete_if_valid_(g));
            g.set_adapter(SimRigAdapter());
            g.show();
            delete(g);
            testCase.verifyFalse(isvalid(g));
        end

    end
end


% ====================================================================== %

function delete_if_valid_(h)
if ~isempty(h) && isvalid(h)
    delete(h);
end
end
