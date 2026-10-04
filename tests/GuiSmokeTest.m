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
