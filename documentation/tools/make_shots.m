function make_shots(which)
% make_shots            - regenerate every wiki screenshot
% make_shots("cal")     - just the calibration GUI set
% make_shots("insp")    - just the stimulus inspector
% make_shots("mon")     - just the standalone live monitor
% make_shots("gui")     - just the generated parameter panel
%
% Regenerates the GUI screenshots the wiki embeds, into documentation/tools/out/.
% Copy what changed into the wiki repo's images/ folder; the wiki is a separate
% checkout (github.com/dstolz/stimgen.wiki) and nothing here writes to it.
%
% Every plotted curve is filled from stimgen's own code paths driven by a
% SIMULATED rig (see SimRigAdapter) -- a synthetic speaker, microphone and
% booth. Nothing is drawn on: the panels hold real measurements of an
% imaginary loudspeaker, made by the same Engine an experiment uses. That is
% what makes the screenshots reproducible on a machine with no hardware, and
% identical from one regeneration to the next (the rig is seeded).
%
% Runs headless: `matlab -batch "cd documentation/tools; make_shots"`.
% uifigures are captured with exportapp, which is the only thing that sees a
% uifigure's contents -- print and getframe both come back blank.

arguments
    which (1,1) string = "all"
end

here = fileparts(mfilename('fullpath'));
addpath(fileparts(fileparts(here)));   % the repo ROOT, never +stimgen itself
addpath(here);

outDir = fullfile(here, 'out');
if ~isfolder(outDir), mkdir(outDir); end

warning('off', 'MATLAB:structOnObject');

if any(which == ["all" "cal"]),  shots_calibration(outDir); end
if any(which == ["all" "mon"]),  shots_livemonitor(outDir); end
if any(which == ["all" "insp"]), shots_inspector(outDir);   end
if any(which == ["all" "gui"]),  shots_paramgui(outDir);    end

fprintf('\nWrote:\n');
d = dir(fullfile(outDir, '*.png'));
for k = 1:numel(d)
    fprintf('  %-34s %7.0f kB\n', d(k).name, d(k).bytes/1024);
end
end

% =====================================================================
function shots_calibration(outDir)
fprintf('=== calibration GUI ===\n');

% This window restores the operator's last settings from a preference group,
% so a screenshot taken on a developer's machine would otherwise show that
% machine's stored mic sensitivity. Park the group for the duration.
saved = park_prefs_();
cleanup = onCleanup(@() restore_prefs_(saved));

% --- offline: no adapter, nothing measured -------------------------------
eng0 = stimgen.calibration.Engine();
gui0 = stimgen.calibration.CalibrationGui(eng0);
settle();
grab(gui0, fullfile(outDir, 'CalibrationGui_offline.png'));
delete(gui0); delete(eng0);

% --- the measurements, run headless on the simulated rig -----------------
% The GUI is built afterwards, on the finished engine, for two reasons: its
% constructor syncs every field from the engine (so Mic Sensitivity shows
% what the reference step measured rather than a stored preference), and it
% restores no preferences at all onto an engine that is already calibrated.
a = SimRigAdapter('HumVrms', 3.0e-6);
eng = stimgen.calibration.Engine(a);
eng.set_configuration(Notes= ...
    "Simulated rig -- documentation screenshots, not a real measurement." + newline + ...
    "Speaker: synthetic closed-field, 3.2 kHz resonance, 9 kHz notch." + newline + ...
    "Microphone: 50 mV/Pa.  Booth: 30 dB SPL floor, 0.99 m path, RT60 60 ms.");

fprintf('reference...\n');
a.CalibratorOn = true;
eng.calibrate_reference();
a.CalibratorOn = false;

fprintf('background...\n');
eng.measure_background(1.0, 3);

fprintf('conduction delay...\n');
[~, latDiag] = eng.measure_conduction_delay();

fprintf('tones...\n');
eng.calibrate_tones();

fprintf('clicks...\n');
eng.calibrate_clicks();
fprintf('test clicks...\n');
eng.test_clicks();

fprintf('swept sine...\n');
eng.calibrate_swept_sine(1.0);

fprintf('filter...\n');
eng.design_filter("tone", NumCoefficients=257, SmoothingOctaves=1/12, ...
    MaxCorrectionDb=15);
eng.test_filter();

% Last, so the response/spectrum panels at the top of every screenshot show
% a tone burst -- the measurement the window is mostly about -- rather than
% the filter test's chirp.
fprintf('test tones...\n');
eng.test_tones(4000, [60 70 80]);

% --- the window ----------------------------------------------------------
gui = stimgen.calibration.CalibrationGui(eng);
gui.set_adapter(a);
gui.Monitor.show_latency(latDiag);   % GUI-side state a fresh window has not got
settle();

tabs = findall(struct(gui).Figure, 'Type', 'uitabgroup');
tabs = tabs(1);

shots = { ...
    'Tones',            'CalibrationGui.png'; ...
    'Clicks',           'CalibrationGui_clicks.png'; ...
    'Swept Sine',       'CalibrationGui_swept.png'; ...
    'Filter Test',      'CalibrationGui_filtertest.png'; ...
    'Background Noise', 'CalibrationGui_background.png'; ...
    'Conduction Delay', 'CalibrationGui_delay.png'};

for k = 1:size(shots, 1)
    select_tab(tabs, shots{k, 1});
    settle();
    grab(gui, fullfile(outDir, shots{k, 2}));
end

% The three Options-menu settings windows. They are separate figures opened
% by private callbacks, so they are triggered through the menu items' own
% MenuSelectedFcn rather than reached directly.
dialogs = { ...
    'Hardware and Analysis Settings...', 'CalibrationGui_hardware_settings.png'; ...
    'Excitation Settings...',            'CalibrationGui_excitation_settings.png'; ...
    'Conduction Delay Settings...',      'CalibrationGui_delay_settings.png'};

before = findall(groot, 'Type', 'figure');
for k = 1:size(dialogs, 1)
    m = findall(struct(gui).Figure, 'Type', 'uimenu', 'Text', dialogs{k, 1});
    feval(m(1).MenuSelectedFcn, m(1), []);
    settle();
    d = setdiff(findall(groot, 'Type', 'figure'), before);
    exportapp(d(1), fullfile(outDir, dialogs{k, 2}));
    fprintf('  -> %s\n', dialogs{k, 2});
    delete(d);
end

eng.save(fullfile(outDir, 'simulated_rig.esgc'));
delete(gui);
end

function saved = park_prefs_()
g = 'StimCalibrationGui';
saved = struct();
if ispref(g)
    saved = getpref(g);
    rmpref(g);
end
end

function restore_prefs_(saved)
g = 'StimCalibrationGui';
if ispref(g), rmpref(g); end
fn = fieldnames(saved);
for k = 1:numel(fn)
    setpref(g, fn{k}, saved.(fn{k}));
end
end

% =====================================================================
function shots_livemonitor(outDir)
fprintf('=== live monitor ===\n');
a = SimRigAdapter('HumVrms', 3.0e-6);
eng = stimgen.calibration.Engine(a);
eng.set_configuration(ShowLivePlots=true);

a.CalibratorOn = true;  eng.calibrate_reference();  a.CalibratorOn = false;

mon = stimgen.calibration.LiveMonitor(eng);
mon.Weightings = "A";
eng.calibrate_tones();
drawnow; pause(0.6);

% Its own window is a traditional figure, not a uifigure, so exportgraphics
% rather than exportapp.
f = monitor_figure(mon);
f.Position = [80 80 1200 780];
f.Color = 'w';
drawnow; pause(0.6);
exportgraphics(f, fullfile(outDir, 'LiveMonitor.png'), Resolution=150, ...
    BackgroundColor='white');
fprintf('  -> LiveMonitor.png\n');
delete(mon); delete(eng);
end

% =====================================================================
function shots_inspector(outDir)
fprintf('=== stimulus inspector ===\n');

s = stimgen.AMnoise;
s.Fs = 48000;
s.Duration = 0.5;
s.AMRate = 20;
s.AMDepth = 1;
s.HighPass = 2000;
s.LowPass = 16000;
s.SoundLevel = 70;
s.ApplyCalibration = false;
s.update_signal;

insp = stimgen.StimInspector(s, "AM noise, 20 Hz, 2-16 kHz");
settle();
tabs = findall(struct(insp).Figure, 'Type', 'uitabgroup');
tabs = tabs(1);

names = {'Waveform', 'StimInspector.png'; ...
         'Spectrum', 'StimInspector_spectrum.png'; ...
         'Spectrogram', 'StimInspector_spectrogram.png'};
for k = 1:size(names, 1)
    select_tab(tabs, names{k, 1});
    insp.refresh();
    settle();
    grab(insp, fullfile(outDir, names{k, 2}));
end
delete(insp);

% The distortion tab needs a tonal signal that actually HAS distortion. A
% synthesized tone has none by construction -- its THD reads -277 dB and the
% bar chart is one bar -- so the tab is shown on a RECORDING of a tone played
% through the simulated rig instead. That is also the stimgen.CapturedSignal
% path the wiki page documents: a microphone record wearing the StimType
% interface so the inspector can characterize it.
t = stimgen.Tone;
t.Fs = 48000;
t.Frequency = 4000;
t.Duration = 0.2;
t.ApplyCalibration = false;
t.update_signal;

a = SimRigAdapter('HumVrms', 3.0e-6);
eng = stimgen.calibration.Engine(a);
a.CalibratorOn = true;  eng.calibrate_reference();  a.CalibratorOn = false;
cap = eng.play_and_capture(2.0 * t.Signal, Repeats=2);
rec = stimgen.CapturedSignal(cap.response, cap.fs);

insp = stimgen.StimInspector(rec, "4 kHz tone, recorded");
settle();
tabs = findall(struct(insp).Figure, 'Type', 'uitabgroup');
select_tab(tabs(1), 'Distortion');
insp.refresh();
settle();
grab(insp, fullfile(outDir, 'StimInspector_distortion.png'));
delete(insp);
end

% =====================================================================
function shots_paramgui(outDir)
fprintf('=== generated parameter panel ===\n');
% Tone, because its panel shows every widget type the generator produces: a
% dropdown (WindowMethod), a checkbox (Apply Calibration), plain numeric
% fields, and -- since Frequency is given a vector -- the expression text
% field a vectorized property renders as.
s = stimgen.Tone;
s.Fs = 48000;
s.Duration = 0.05;
s.Frequency = [1000 2000 4000 8000 16000];
s.SoundLevel = [50 60 70];
s.update_signal;

f = uifigure('Name', 'Tone', 'Position', [200 200 470 490]);
g = uigridlayout(f, [1 1]);
p = uipanel(g, 'Title', 'Tone', 'FontWeight', 'bold');
s.create_gui(p);
drawnow; pause(0.8); drawnow;
exportapp(f, fullfile(outDir, 'StimType_parameter_panel.png'));
delete(f);
end

% =====================================================================
% helpers
% =====================================================================
function select_tab(tg, title)
hit = find(strcmp({tg.Children.Title}, title), 1);
if isempty(hit)
    error('No tab titled "%s". Have: %s', title, strjoin({tg.Children.Title}, ', '));
end
tg.SelectedTab = tg.Children(hit);
end

function settle()
% uifigure content is drawn asynchronously; a screenshot taken too early
% catches half-built axes.
drawnow; pause(0.7); drawnow; pause(0.3);
end

function grab(obj, ffn)
f = struct(obj).Figure;
drawnow;
exportapp(f, ffn);
fprintf('  -> %s\n', ffn);
end

function f = monitor_figure(mon)
s = struct(mon);
fn = fieldnames(s);
for k = 1:numel(fn)
    v = s.(fn{k});
    if isa(v, 'matlab.ui.Figure') && isvalid(v)
        f = v;
        return
    end
end
% Fall back to the axes' ancestor.
f = ancestor(s.AxSignal, 'figure');
end
