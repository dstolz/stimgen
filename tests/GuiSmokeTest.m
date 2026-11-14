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

            % Menu actions whose code lives in local functions of method
            % files: the paths most exposed to a change of method access.
            invoke_menu_(testCase, 'Export Signal to Workspace');
            invoke_menu_(testCase, 'Export All Signals to Workspace');
            invoke_menu_(testCase, 'Export Bank as StimType Objects');
            testCase.verifyTrue(evalin('base', 'exist(''y'', ''var'') == 1'));
            testCase.verifyTrue(evalin('base', 'exist(''signals'', ''var'') == 1'));
            testCase.verifyTrue(evalin('base', 'exist(''stimBank'', ''var'') == 1'));
            evalin('base', 'clear y signals stimBank');

            % Windows the player opens and does not wait on.
            before = findall(groot, 'Type', 'figure');
            invoke_menu_(testCase, 'Capture Settings...');
            invoke_menu_(testCase, 'Open Calibration GUI');
            delete(setdiff(findall(groot, 'Type', 'figure'), before));

            p.set_control_visibility(ISI=false, SampleRate=false);
            p.set_control_visibility(ISI=true, SampleRate=true);
            p.Fs = 44100;   % rewrites and regenerates every bank item
            testCase.verifyEqual(p.StimPlayObjs(1).CurrentStimObj.Fs, 44100);

            ffn = fullfile(tmp.Folder, 'smoke.spl');
            p.save_bank(ffn);
            testCase.verifyTrue(isfile(ffn));
            testCase.verifyEqual(p.BankFile, string(ffn));
            p.load_bank(ffn);
            testCase.verifyEqual(numel(p.StimPlayObjs), n + 1);

            delete(p);
            testCase.verifyFalse(isvalid(p));
        end

        function presentationLogOfADryRun(testCase)
            % An offline player has no hardware, so Run is a dry run: the
            % timer runs, the presentation log fills, and nothing asks for
            % confirmation. Every presentation carries the generation record
            % of the stimulus it presented; the log is then saved and read
            % back. A dry run is not saved automatically.
            if ~testCase.GuiOk
                fprintf('GUISMOKE skipped presentationLogOfADryRun\n');
                return
            end
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            autoDir = fullfile(tmp.Folder, 'auto');

            p = stimgen.StimPlayer();
            testCase.addTeardown(@() delete_if_valid_(p));
            p.Fs = 48000;
            p.ISI = [0.05 0.05];
            p.SelectionType = "Serial";
            p.PresentationLogDir = string(autoDir);

            % Two items, two combinations each, Reps a multiple of the
            % combination count and every Duration inside the ISI: nothing
            % for the pre-run check to ask about.
            p.open_stim(stimgen.Tone('Fs', 48000, 'Duration', 0.02, ...
                'ApplyCalibration', false, 'Frequency', [1000 2000]), Name="tones");
            p.open_stim(stimgen.DMR('Fs', 48000, 'Duration', 0.02, ...
                'ApplyCalibration', false, 'NumCarriers', 13, 'HighFrequency', 8000, ...
                'Seed', [5 6]), Name="ripples");
            p.StimPlayObjs(1).Reps = 2;
            p.StimPlayObjs(2).Reps = 2;

            menu = find_menu_('Export Presentation Log...');
            testCase.assertNotEmpty(menu);
            testCase.verifyEqual(string(menu(1).Enable), "off");
            testCase.verifyError(@() p.save_presentation_log(fullfile(tmp.Folder, 'none.mat')), ...
                'stimgen:StimPlayer:NoPresentationLog');

            p.playback_control("Run");
            wait_for_run_(p, 4);
            testCase.assertEqual(numel(p.StimOrder), 4, 'the dry run did not make its 4 presentations');

            testCase.verifyEqual(p.StimOrder,   [1; 1; 2; 2]);
            testCase.verifyEqual(p.StimVariant, [1; 2; 1; 2]);
            testCase.verifySize(p.StimLateness, [4 1]);
            testCase.verifyGreaterThanOrEqual(min(p.StimLateness), 0);
            testCase.verifySize(p.StimRecord, [4 1]);
            for k = 1:4
                r = p.StimRecord{k};
                testCase.assertNotEmpty(r, sprintf('presentation %d has no record', k));
                testCase.verifyEqual(r.VariantIndex, p.StimVariant(k));
            end
            testCase.verifyEqual(p.StimRecord{1}.Class, "stimgen.Tone");
            testCase.verifyEqual(p.StimRecord{1}.VariantValues.Frequency, 1000);
            testCase.verifyEqual(p.StimRecord{2}.VariantValues.Frequency, 2000);
            testCase.verifyEqual(p.StimRecord{3}.Class, "stimgen.DMR");
            testCase.verifyEqual(p.StimRecord{3}.Seed, 5);
            testCase.verifyEqual(p.StimRecord{4}.Seed, 6);

            testCase.verifyFalse(p.RunInfo.HardwareRun);
            testCase.verifyTrue(p.RunInfo.Completed);
            testCase.verifyEqual(p.RunInfo.NPresented, 4);
            testCase.verifyEqual(p.RunInfo.NTotal, 4);
            % A dry run is not written anywhere on its own.
            testCase.verifyEqual(p.PresentationLogFile, "");
            testCase.verifyFalse(isfolder(autoDir));
            testCase.verifyEqual(string(menu(1).Enable), "on");

            ffn = p.save_presentation_log(fullfile(tmp.Folder, 'dry'));
            testCase.verifyTrue(endsWith(ffn, ".mat"));
            testCase.verifyEqual(p.PresentationLogFile, ffn);
            L = load(ffn);
            testCase.verifyEqual(L.FormatVersion, 1);
            testCase.verifyFalse(L.HardwareRun);
            testCase.verifyTrue(L.Completed);
            testCase.verifyEqual(L.NPresented, 4);
            testCase.verifyEqual(L.Fs, 48000);
            testCase.verifyEqual(L.ISI, [0.05 0.05]);
            testCase.verifyEqual(L.BankNames, ["tones"; "ripples"]);
            testCase.verifyEqual(L.StimOrder,   [1; 1; 2; 2]);
            testCase.verifyEqual(L.StimVariant, [1; 2; 1; 2]);
            testCase.verifySize(L.StimLateness, [4 1]);
            testCase.verifyEqual(L.StimRecord{4}.Seed, 6);
            testCase.verifyEqual(L.Bank.NItems, 2);

            % The file alone identifies what presentation 4 played: the
            % bank item restored from the snapshot, pinned to the logged
            % combination, makes the segment the record describes.
            r = stimgen.StimType.fromStruct(L.Bank.Items{L.StimOrder(4)}.StimObj);
            testCase.verifyClass(r, 'stimgen.DMR');
            r.VariantReselectOnUpdate = false;
            r.set_variant_index(L.StimVariant(4));
            again = r.generation_record();
            testCase.verifyEqual(again.Seed, L.StimRecord{4}.Seed);
            testCase.verifyEqual(again.RawRms, L.StimRecord{4}.RawRms);
            testCase.verifyEqual(again.Envelope(1).RateKnots, L.StimRecord{4}.Envelope(1).RateKnots);

            delete(p);
        end

        function hardwareRunSavesItsLog(testCase)
            % With hardware output (a host exposing the buffer and trigger
            % parameters), the log is written to PresentationLogDir when the
            % run ends, without asking -- it is otherwise in memory only.
            if ~testCase.GuiOk
                fprintf('GUISMOKE skipped hardwareRunSavesItsLog\n');
                return
            end
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            autoDir = fullfile(tmp.Folder, 'auto');

            host = FakeHardwareHost();
            p = stimgen.StimPlayer(host);
            testCase.addTeardown(@() delete_if_valid_(p));
            p.Fs = 48000;
            p.ISI = [0.05 0.05];
            p.SelectionType = "Serial";
            p.PresentationLogDir = string(autoDir);
            p.open_stim(stimgen.Tone('Fs', 48000, 'Duration', 0.02, ...
                'ApplyCalibration', false, 'Frequency', [1000 2000]), Name="tones");
            p.StimPlayObjs(1).Reps = 2;

            p.playback_control("Run");
            wait_for_run_(p, 2);
            testCase.assertEqual(numel(p.StimOrder), 2, 'the run did not make its 2 presentations');

            testCase.verifyTrue(p.RunInfo.HardwareRun);
            testCase.verifyTrue(p.RunInfo.Completed);
            % The buffers were loaded and both slots triggered (1 then 0).
            testCase.verifyEqual(host.Parameters.x_Trigger_0.NumWrites, 2);
            testCase.verifyEqual(host.Parameters.x_Trigger_1.NumWrites, 2);
            testCase.verifyEqual(numel(host.Parameters.BufferData_0.Value), p.StimRecord{1}.N + 2);
            testCase.verifyFalse(host.Connected, 'the hardware was not released after the run');

            ffn = p.PresentationLogFile;
            testCase.assertTrue(strlength(ffn) > 0, 'the hardware run''s log was not saved');
            testCase.verifyTrue(isfile(ffn));
            testCase.verifyTrue(startsWith(ffn, string(autoDir)));
            [~, name] = fileparts(ffn);
            testCase.verifyNotEmpty(regexp(char(name), '^stimgen_run_\d{8}_\d{6}$', 'once'));

            L = load(ffn);
            testCase.verifyTrue(L.HardwareRun);
            testCase.verifyTrue(L.Completed);
            testCase.verifyEqual(L.NPresented, 2);
            testCase.verifyEqual(L.StimVariant, [1; 2]);
            testCase.verifyEqual(L.StimRecord{2}.VariantValues.Frequency, 2000);
            testCase.verifyNotEmpty(L.RunStoppedAt);

            % Turned off, a hardware run is not written.
            p.PresentationLogDir = "";
            p.playback_control("Run");
            wait_for_run_(p, 2);
            testCase.assertEqual(numel(p.StimOrder), 2);
            testCase.verifyEqual(p.PresentationLogFile, "");
            testCase.verifyEqual(numel(dir(fullfile(autoDir, '*.mat'))), 1);

            delete(p);
        end

        function backgroundRowsFollowTheDropdown(testCase)
            % Choosing a Background in the bank editor changes WHICH rows the
            % stimulus has, so the panel is rebuilt around the edit -- the
            % one path where a value change, not a button, rebuilds it.
            if ~testCase.GuiOk
                fprintf('GUISMOKE skipped backgroundRowsFollowTheDropdown\n');
                return
            end
            % An edit made in the panel is remembered for the stimulus type
            % (pref StimPlayer/StimSettings); put the user's own back.
            had = ispref('StimPlayer', 'StimSettings');
            old = [];
            if had
                old = getpref('StimPlayer', 'StimSettings');
            end
            testCase.addTeardown(@() restore_stim_settings_(had, old));

            p = stimgen.StimPlayer();
            testCase.addTeardown(@() delete_if_valid_(p));
            p.Fs = 48000;
            p.open_stim(stimgen.Tone('Fs', 48000, 'Duration', 0.02, ...
                'ApplyCalibration', false), Name="tone");
            stim = p.StimPlayObjs(1).CurrentStimObj;

            lb = findall(groot, 'Tag', 'BankList');
            testCase.assertNotEmpty(lb);
            lb = lb(1);
            lb.Value = 1;
            p.on_bank_selection_changed(lb, []);

            testCase.assertNotEmpty(findall(groot, 'Tag', 'Background'));
            testCase.verifyEmpty(findall(groot, 'Tag', 'BackgroundLevel'));

            choose_background_(testCase, "Noise");
            testCase.verifyEqual(stim.Background, "Noise");
            testCase.verifyNotEmpty(findall(groot, 'Tag', 'BackgroundLevel'));
            testCase.verifyNotEmpty(findall(groot, 'Tag', 'BackgroundHighPass'));
            testCase.verifyEmpty(findall(groot, 'Tag', 'BackgroundFrequency'));

            choose_background_(testCase, "Tone");
            testCase.verifyNotEmpty(findall(groot, 'Tag', 'BackgroundFrequency'));
            testCase.verifyEmpty(findall(groot, 'Tag', 'BackgroundHighPass'));

            choose_background_(testCase, "None");
            testCase.verifyEqual(stim.Background, "None");
            testCase.verifyEmpty(findall(groot, 'Tag', 'BackgroundLevel'));
            testCase.verifyNotEmpty(findall(groot, 'Tag', 'Background'));

            delete(p);
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

            % Every View item redraws every panel against real tables.
            for t = cellstr(stimgen.calibration.LiveMonitor.WeightingTypes)
                invoke_menu_(testCase, sprintf('%s-weighting', t{1}));
            end
            invoke_menu_(testCase, 'None');
            unitMenu = find_menu_('Spectrum Y-Axis');
            testCase.assertNotEmpty(unitMenu);
            for m = flip(unitMenu.Children(:).')
                feval(m.MenuSelectedFcn, m, []);
            end
            for item = {'Previous-Measurement Ghost', 'Transfer Drive-Voltage Axis', ...
                        'Full-Resolution Waveforms'}
                invoke_menu_(testCase, item{1});   % toggle
                invoke_menu_(testCase, item{1});   % and back
            end
            invoke_menu_(testCase, 'Print Calibration Summary');

            % The three settings windows: modal, but nothing waits on them.
            before = findall(groot, 'Type', 'figure');
            invoke_menu_(testCase, 'Hardware and Analysis Settings...');
            invoke_menu_(testCase, 'Conduction Delay Settings...');
            invoke_menu_(testCase, 'Excitation Settings...');
            opened = setdiff(findall(groot, 'Type', 'figure'), before);
            testCase.verifyEqual(sort(string({opened.Name})), ...
                sort(["Hardware and Analysis Settings", "Conduction Delay Settings", ...
                      "Excitation Settings"]));
            % Opening one again raises it rather than making a second.
            invoke_menu_(testCase, 'Excitation Settings...');
            testCase.verifyEqual(numel(setdiff(findall(groot, 'Type', 'figure'), before)), 3);
            delete(g);
            testCase.verifyFalse(isvalid(g));
        end

        function calibrationGuiLive(testCase)
            % The measurement buttons on a live engine with the simulated rig,
            % each parameter window answered by a timer the way an operator
            % would answer it. with_busy_state_ reports a failure in the
            % window rather than throwing, so each step is checked by what it
            % left in the engine.
            if ~testCase.GuiOk
                fprintf('GUISMOKE skipped calibrationGuiLive\n');
                return
            end
            rig = SimRigAdapter('CalibratorOn', true);
            eng = stimgen.calibration.Engine(rig);
            eng.calibrate_reference();
            rig.CalibratorOn = false;

            g = stimgen.calibration.CalibrationGui(eng);
            testCase.addTeardown(@() delete_if_valid_(g));
            g.show();

            t = answer_dialog_(testCase, 'Measure Background', {});
            press_(testCase, 'Measure Background');
            verify_answered_(testCase, t);
            testCase.verifyTrue(isfield(eng.CalibrationData, 'background'));

            press_(testCase, 'Measure Conduction Delay');   % no parameter window
            testCase.verifyTrue(eng.ConductionDelay.valid);

            t = answer_dialog_(testCase, 'Tone Calibration', {'500 1000 2000 4000'});
            press_(testCase, 'Calibrate Tones');
            verify_answered_(testCase, t);
            testCase.assertTrue(isfield(eng.CalibrationData, 'tone'));
            testCase.verifyEqual(eng.CalibrationData.tone.frequency, [500; 1000; 2000; 4000]);

            t = answer_dialog_(testCase, 'Test Tone Lookup Table', {});
            press_(testCase, 'Test Tones');
            verify_answered_(testCase, t);
            testCase.verifyTrue(isfield(eng.CalibrationData, 'toneTest'));

            % Click durations are typed in ms and reach the engine in s.
            t = answer_dialog_(testCase, 'Click Calibration', {'0.1 0.2 0.4'});
            press_(testCase, 'Calibrate Clicks');
            verify_answered_(testCase, t);
            testCase.assertTrue(isfield(eng.CalibrationData, 'click'));
            testCase.verifyEqual(eng.CalibrationData.click.duration, [1e-4; 2e-4; 4e-4], ...
                'AbsTol', 1e-12);

            t = answer_dialog_(testCase, 'Test Click Lookup Table', {});
            press_(testCase, 'Test Clicks');
            verify_answered_(testCase, t);
            testCase.verifyTrue(isfield(eng.CalibrationData, 'clickTest'));

            delete(g);
            testCase.verifyFalse(isvalid(g));
        end

    end
end


% ====================================================================== %

function wait_for_run_(p, nExpected)
% Let the player's timer run until it has made nExpected presentations and
% stopped, or 30 s have passed. Timer callbacks run while MATLAB pauses.
started = tic;
while toc(started) < 30
    running = ~isempty(p.Timer) && isvalid(p.Timer) && strcmp(p.Timer.Running, 'on');
    if numel(p.StimOrder) >= nExpected && ~running
        return
    end
    pause(0.02);
end
end


function restore_stim_settings_(had, old)
% Put the remembered-settings pref back as it was before a test edited a
% stimulus through the panel.
if had
    setpref('StimPlayer', 'StimSettings', old);
elseif ispref('StimPlayer', 'StimSettings')
    rmpref('StimPlayer', 'StimSettings');
end
end


function choose_background_(testCase, value)
% Pick a Background in the parameter panel as a click on the dropdown would:
% set the widget, then run its callback with the event a click delivers.
dd = findall(groot, 'Tag', 'Background');
testCase.assertNotEmpty(dd, 'no Background dropdown in the parameter panel');
dd = dd(1);
previous = dd.Value;
dd.Value = value;
feval(dd.ValueChangedFcn, dd, struct('Value', dd.Value, 'PreviousValue', previous));
drawnow;
end


function invoke_menu_(testCase, text)
% Run a menu item's callback as a click would.
m = find_menu_(text);
testCase.assertNotEmpty(m, sprintf('no menu item "%s"', text));
feval(m(1).MenuSelectedFcn, m(1), []);
end


function m = find_menu_(text)
items = findall(groot, 'Type', 'uimenu');
m = items(strcmp(strrep(string({items.Text}), "&", ""), text));
end


function press_(testCase, text)
% Run a button's callback as a click would.
items = findall(groot, 'Type', 'uibutton');
b = items(strcmp(string({items.Text}), text));
testCase.assertNotEmpty(b, sprintf('no button "%s"', text));
feval(b(1).ButtonPushedFcn, b(1), []);
end


function t = answer_dialog_(testCase, title, texts)
% Answer the next parameter window called title: fill its text fields, in
% the order given, then press OK. The window is left one tick after it
% appears before OK is pressed, so the dialog is waiting by then; if OK
% still leaves it open, an accepted value is resumed again and a refused
% one (or a window that will not go) is cancelled, so a test can never hang
% on it. The timer's UserData says which happened.
t = timer('ExecutionMode', 'fixedSpacing', 'Period', 0.25, 'TasksToExecute', 240, ...
    'UserData', struct('state', "waiting", 'tries', 0), ...
    'TimerFcn', @(tm, ~) answer_tick_(tm, title, texts));
testCase.addTeardown(@() stop_and_delete_(t));
start(t);
end


function answer_tick_(tm, title, texts)
u = tm.UserData;
f = findall(groot, 'Type', 'figure', 'Name', title);
if isempty(f)
    if u.state == "answered"
        u.state = "done";
        tm.UserData = u;
        stop(tm);
    end
    return
end
f = f(1);
switch u.state
    case "waiting"
        u.state = "seen";                % let the dialog reach uiwait
    case "seen"
        edits = findall(f, 'Type', 'uieditfield');
        edits = flip(edits(:).');        % creation order
        for k = 1:min(numel(texts), numel(edits))
            edits(k).Value = texts{k};
        end
        ok = findall(f, 'Type', 'uibutton', 'Text', 'OK');
        u.state = "answered";
        tm.UserData = u;
        feval(ok(1).ButtonPushedFcn, ok(1), []);
        return
    case "answered"
        u.tries = u.tries + 1;
        accepted = isstruct(f.UserData) && isfield(f.UserData, 'ok') && f.UserData.ok;
        if accepted && u.tries < 8
            uiresume(f);                 % accepted before the wait began
        else
            msg = findall(f, 'Type', 'uilabel');
            u.state = "refused: " + strjoin(string({msg.Text}), ' | ');
            tm.UserData = u;
            cancel = findall(f, 'Type', 'uibutton', 'Text', 'Cancel');
            feval(cancel(1).ButtonPushedFcn, cancel(1), []);
            return
        end
end
tm.UserData = u;
end


function verify_answered_(testCase, t)
% The action has returned, so an accepted window is gone: "answered" or
% "done" both mean it was accepted.
state = t.UserData.state;
testCase.verifyTrue(any(state == ["answered", "done"]), ...
    sprintf('the parameter window was not accepted (%s)', state));
stop_and_delete_(t);
end


function stop_and_delete_(t)
if isvalid(t)
    stop(t);
    delete(t);
end
end


function delete_if_valid_(h)
if ~isempty(h) && isvalid(h)
    delete(h);
end
end
