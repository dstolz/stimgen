function build_ui_(obj)
% build_ui_(obj) - Build the StimInspector uifigure and all UI components.
%
% Layout: a header line across the top (with the Units control at its right
% end), an information column on the left (metrics table, a recording's
% warnings, parameter table), a tab group of plots on the right, and a status
% line along the bottom.

tip = @(key) stimgen.util.tooltip('StimInspector', key);

f = uifigure('Name', 'Stimulus Inspector', 'Position', [140 90 1180 800]);
f.DeleteFcn = @(~,~) delete(obj);
obj.Figure = f;

g = uigridlayout(f);
g.ColumnWidth = {340, '1x'};
g.RowHeight   = {30, '1x', 22};
g.Padding     = [6 6 6 6];
g.RowSpacing  = 4;
g.ColumnSpacing = 6;

% ---- Header ----
hg = uigridlayout(g, [1 3]);
hg.Layout.Row    = 1;
hg.Layout.Column = [1 2];
hg.ColumnWidth   = {'1x', 'fit', 230};
hg.Padding       = [0 0 0 0];
hg.ColumnSpacing = 6;

h = uilabel(hg, 'Text', 'No stimulus selected.', ...
    'FontWeight', 'bold', 'FontSize', 13);
h.Layout.Column = 1;
obj.handles.HeaderLabel = h;

% Only a recording that came with a microphone sensitivity can be shown as
% sound; read_capture_ enables this for one and sets it to follow the choice.
lbl = uilabel(hg, 'Text', 'Units:', 'HorizontalAlignment', 'right');
lbl.Layout.Column = 2;
lbl.Tooltip = tip('UnitsDD');

d = uidropdown(hg);
d.Items     = {'Sound pressure (Pa, dB SPL)', 'Signal (V, dB re 1 V)'};
d.ItemsData = {"acoustic", "electrical"};
d.Value     = "electrical";
d.Enable    = 'off';
d.Layout.Column = 3;
d.Tooltip   = tip('UnitsDD');
d.ValueChangedFcn = @(src, ~) obj.set_units(string(src.Value));
obj.handles.UnitsDD = d;

% ---- Left: information column ----
infoG = uigridlayout(g);
infoG.Layout.Row    = 2;
infoG.Layout.Column = 1;
infoG.ColumnWidth   = {'1x'};
infoG.RowHeight     = {'3x', 0, '2x'};   % warnings row folded until needed
infoG.Padding       = [0 0 0 0];
infoG.RowSpacing    = 6;
obj.handles.InfoGrid = infoG;

obj.handles.MetricsTable = make_table_(infoG, 1, 'Signal Metrics', {'Metric', 'Value'});
[obj.handles.WarningsPanel, obj.handles.WarningsArea] = make_warnings_(infoG, 2, tip('Warnings'));
obj.handles.ParamsTable  = make_table_(infoG, 3, 'Parameters',     {'Parameter', 'Value'});

% ---- Right: plot tabs ----
tg = uitabgroup(g);
tg.Layout.Row    = 2;
tg.Layout.Column = 2;
% Only the visible tab is drawn, so a tab has to be brought up to date as it
% is selected (see update_plots_). The flush first lets a tab shown for the
% first time lay its axes out before anything is drawn into them.
tg.SelectionChangedFcn = @(~,~) tab_changed_(obj);
obj.handles.TabGroup = tg;

build_waveform_tab_(obj, tg);
build_spectrum_tab_(obj, tg, tip);
build_spectrogram_tab_(obj, tg, tip);
build_distortion_tab_(obj, tg);
build_bands_tab_(obj, tg, tip);
build_sound_level_tab_(obj, tg, tip);

% ---- Status line ----
h = uilabel(g, 'Text', 'Ready.', 'HorizontalAlignment', 'left', ...
    'FontColor', [0.35 0.35 0.35]);
h.Layout.Row    = 3;
h.Layout.Column = [1 2];
obj.handles.StatusLabel = h;

% ---- Toolbar ----
tb = uitoolbar(f);

obj.handles.RefreshTool = uipushtool(tb, 'Tooltip', tip('RefreshTool'), ...
    'Icon', stimgen.util.toolbar_icon('refresh'), ...
    'ClickedCallback', @(~,~) obj.refresh());

obj.handles.PlayTool = uipushtool(tb, 'Tooltip', tip('PlayTool'), 'Separator', 'on', ...
    'Icon', stimgen.util.toolbar_icon('play'), ...
    'ClickedCallback', @(~,~) obj.play_());

obj.handles.ExportTool = uipushtool(tb, 'Tooltip', tip('ExportTool'), ...
    'Icon', stimgen.util.toolbar_icon('save'), ...
    'ClickedCallback', @(~,~) obj.export_());

movegui(f, 'onscreen');
end % build_ui_


% =========================================================================
% Inline helpers called only from build_ui_
% =========================================================================

function tab_changed_(obj)
% Draw the newly selected tab once its layout is settled.
if ~obj.is_open()
    return
end
drawnow
obj.update_plots_(obj.Metrics);
end

function t = make_table_(parent, row, titleText, columnNames)
% make_table_(parent, row, titleText, columnNames) - Titled read-only table.
pnl = uipanel(parent, 'Title', titleText, 'FontWeight', 'bold');
pnl.Layout.Row    = row;
pnl.Layout.Column = 1;

pg = uigridlayout(pnl);
pg.ColumnWidth = {'1x'};
pg.RowHeight   = {'1x'};
pg.Padding     = [2 2 2 2];

t = uitable(pg);
t.ColumnName     = columnNames;
t.RowName        = {};
t.ColumnWidth    = {150, 'auto'};
t.ColumnEditable = [false false];
t.Data           = cell(0, 2);
end


function [pnl, area] = make_warnings_(parent, row, tooltipText)
% make_warnings_(parent, row, tooltipText) - The warning list for a recording.
% A read-only text area rather than table rows: a warning is a sentence, and
% a table cell clips a sentence to the width of its column.
pnl = uipanel(parent, 'Title', 'Warnings', 'FontWeight', 'bold', ...
    'ForegroundColor', [0.70 0.15 0.10], 'Visible', 'off');
pnl.Layout.Row    = row;
pnl.Layout.Column = 1;

pg = uigridlayout(pnl);
pg.ColumnWidth = {'1x'};
pg.RowHeight   = {'1x'};
pg.Padding     = [2 2 2 2];

area = uitextarea(pg, 'Editable', 'off', 'Value', {''}, ...
    'FontColor', [0.55 0.12 0.08], 'Tooltip', tooltipText);
end


function build_waveform_tab_(obj, tg)
% Time-domain tab: waveform with amplitude envelope, plus envelope in dB.
tab = uitab(tg, 'Title', 'Waveform');

tgrid = uigridlayout(tab);
tgrid.ColumnWidth = {'1x'};
tgrid.RowHeight   = {'2x', '1x'};
tgrid.Padding     = [6 6 6 6];

ax = uiaxes(tgrid);
ax.Layout.Row    = 1;
ax.Layout.Column = 1;
grid(ax, 'on');
box(ax, 'on');
title(ax, 'Time Domain');
xlabel(ax, 'time (ms)');
ylabel(ax, 'amplitude');
obj.handles.AxWave = ax;

ax = uiaxes(tgrid);
ax.Layout.Row    = 2;
ax.Layout.Column = 1;
grid(ax, 'on');
box(ax, 'on');
title(ax, 'Envelope (dB re peak)');
xlabel(ax, 'time (ms)');
ylabel(ax, 'dB');
obj.handles.AxEnvelope = ax;
end


function build_spectrum_tab_(obj, tg, tip)
% Magnitude-spectrum tab with axis-scale, harmonic-marker, density and
% noise-floor options.
tab = uitab(tg, 'Title', 'Spectrum');

tgrid = uigridlayout(tab);
tgrid.ColumnWidth = {150, 130, 130, 130, '1x'};
tgrid.RowHeight   = {24, '1x'};
tgrid.Padding     = [6 6 6 6];

c = uicheckbox(tgrid, 'Text', 'Log frequency axis', 'Value', true);
c.Layout.Row    = 1;
c.Layout.Column = 1;
c.ValueChangedFcn = @(~,~) obj.update_plots_(obj.Metrics);
obj.handles.LogFreqCheck = c;

c = uicheckbox(tgrid, 'Text', 'Mark harmonics', 'Value', true);
c.Layout.Row    = 1;
c.Layout.Column = 2;
c.ValueChangedFcn = @(~,~) obj.update_plots_(obj.Metrics);
obj.handles.MarkHarmonicsCheck = c;

c = uicheckbox(tgrid, 'Text', 'Density (per Hz)', 'Value', false);
c.Layout.Row    = 1;
c.Layout.Column = 3;
c.Tooltip       = tip('DensityCheck');
c.ValueChangedFcn = @(~,~) obj.update_plots_(obj.Metrics);
obj.handles.DensityCheck = c;

c = uicheckbox(tgrid, 'Text', 'Noise floor', 'Value', true);
c.Layout.Row    = 1;
c.Layout.Column = 4;
c.Tooltip       = tip('NoiseFloorCheck');
c.ValueChangedFcn = @(~,~) obj.update_plots_(obj.Metrics);
obj.handles.NoiseFloorCheck = c;

ax = uiaxes(tgrid);
ax.Layout.Row    = 2;
ax.Layout.Column = [1 5];
grid(ax, 'on');
box(ax, 'on');
title(ax, 'Magnitude Spectrum');
xlabel(ax, 'frequency (Hz)');
ylabel(ax, 'magnitude (dB re full scale)');
obj.handles.AxSpectrum = ax;
end


function build_spectrogram_tab_(obj, tg, tip)
% Spectrogram tab with a selectable FFT length and window function.
tab = uitab(tg, 'Title', 'Spectrogram');

tgrid = uigridlayout(tab);
tgrid.ColumnWidth = {90, 110, 80, 130, 150, 140, '1x'};
tgrid.RowHeight   = {24, '1x'};
tgrid.Padding     = [6 6 6 6];

lbl = uilabel(tgrid, 'Text', 'FFT length:', 'HorizontalAlignment', 'right');
lbl.Layout.Row    = 1;
lbl.Layout.Column = 1;

d = uidropdown(tgrid);
d.Items     = {'128', '256', '512', '1024', '2048'};
d.ItemsData = [128 256 512 1024 2048];
d.Value     = 512;
d.Layout.Row    = 1;
d.Layout.Column = 2;
d.ValueChangedFcn = @(~,~) obj.update_plots_(obj.Metrics);
obj.handles.SpecNfftDD = d;

lbl = uilabel(tgrid, 'Text', 'Window:', 'HorizontalAlignment', 'right');
lbl.Layout.Row    = 1;
lbl.Layout.Column = 3;

d = uidropdown(tgrid);
d.Items     = {'Hann', 'Rectangular', 'Hamming', 'Blackman', 'Blackman-Harris', 'Flat Top', 'Triangular', 'Bartlett'};
d.ItemsData = {'hann', 'rectwin', 'hamming', 'blackman', 'blackmanharris', 'flattopwin', 'triang', 'bartlett'};
d.Value     = 'hann';
d.Layout.Row    = 1;
d.Layout.Column = 4;
d.ValueChangedFcn = @(~,~) obj.update_plots_(obj.Metrics);
obj.handles.SpecWindowDD = d;

c = uicheckbox(tgrid, 'Text', 'Log frequency axis', 'Value', false);
c.Layout.Row    = 1;
c.Layout.Column = 5;
c.ValueChangedFcn = @(~,~) obj.update_plots_(obj.Metrics);
obj.handles.SpecLogFreqCheck = c;

c = uicheckbox(tgrid, 'Text', 'Density (per Hz)', 'Value', false);
c.Layout.Row    = 1;
c.Layout.Column = 6;
c.Tooltip       = tip('DensityCheck');
c.ValueChangedFcn = @(~,~) obj.update_plots_(obj.Metrics);
obj.handles.SpecDensityCheck = c;

ax = uiaxes(tgrid);
ax.Layout.Row    = 2;
ax.Layout.Column = [1 7];
box(ax, 'on');
title(ax, 'Spectrogram');
xlabel(ax, 'time (ms)');
ylabel(ax, 'frequency (Hz)');
obj.handles.AxSpectrogram = ax;
end


function build_distortion_tab_(obj, tg)
% Harmonic-distortion tab: harmonic levels relative to the fundamental.
tab = uitab(tg, 'Title', 'Distortion');

tgrid = uigridlayout(tab);
tgrid.ColumnWidth = {'1x'};
tgrid.RowHeight   = {'1x', 150};
tgrid.Padding     = [6 6 6 6];

ax = uiaxes(tgrid);
ax.Layout.Row    = 1;
ax.Layout.Column = 1;
grid(ax, 'on');
box(ax, 'on');
title(ax, 'Harmonic Levels');
xlabel(ax, 'harmonic');
ylabel(ax, 'dB re fundamental');
obj.handles.AxHarmonics = ax;

t = uitable(tgrid);
t.Layout.Row     = 2;
t.Layout.Column  = 1;
t.ColumnName     = {'Harmonic', 'Frequency (Hz)', 'Level (dB re F0)', 'Amplitude (%)', 'Level (dB re 1)'};
t.RowName        = {};
t.ColumnEditable = false(1, 5);
t.Data           = cell(0, 5);
obj.handles.HarmonicsTable = t;
end


function build_bands_tab_(obj, tg, tip)
% Fractional-octave band levels, with the noise floor under them.
tab = uitab(tg, 'Title', 'Bands');

tgrid = uigridlayout(tab);
tgrid.ColumnWidth = {70, 110, 80, 90, 130, '1x'};
tgrid.RowHeight   = {24, '1x', 170};
tgrid.Padding     = [6 6 6 6];

lbl = uilabel(tgrid, 'Text', 'Bands:', 'HorizontalAlignment', 'right');
lbl.Layout.Row    = 1;
lbl.Layout.Column = 1;

d = uidropdown(tgrid);
d.Items     = {'Octave', '1/3 octave', '1/6 octave', '1/12 octave'};
d.ItemsData = [1 3 6 12];
d.Value     = 3;
d.Layout.Row    = 1;
d.Layout.Column = 2;
d.Tooltip   = tip('BandFractionDD');
d.ValueChangedFcn = @(~,~) obj.update_plots_(obj.Metrics);
obj.handles.BandFractionDD = d;

lbl = uilabel(tgrid, 'Text', 'Weighting:', 'HorizontalAlignment', 'right');
lbl.Layout.Row    = 1;
lbl.Layout.Column = 3;

d = uidropdown(tgrid);
d.Items     = {'Z (none)', 'A', 'C'};
d.ItemsData = {"Z", "A", "C"};
d.Value     = "Z";
d.Layout.Row    = 1;
d.Layout.Column = 4;
d.Tooltip   = tip('BandWeightingDD');
d.ValueChangedFcn = @(~,~) obj.update_plots_(obj.Metrics);
obj.handles.BandWeightingDD = d;

c = uicheckbox(tgrid, 'Text', 'Noise floor', 'Value', true);
c.Layout.Row    = 1;
c.Layout.Column = 5;
c.Tooltip       = tip('NoiseFloorCheck');
c.ValueChangedFcn = @(~,~) obj.update_plots_(obj.Metrics);
obj.handles.BandNoiseCheck = c;

ax = uiaxes(tgrid);
ax.Layout.Row    = 2;
ax.Layout.Column = [1 6];
grid(ax, 'on');
box(ax, 'on');
title(ax, 'Band Levels');
xlabel(ax, 'band centre (Hz)');
ylabel(ax, 'band level (dB)');
obj.handles.AxBands = ax;

t = uitable(tgrid);
t.Layout.Row     = 3;
t.Layout.Column  = [1 6];
t.ColumnName     = {'Centre (Hz)', 'Level', 'Noise floor', 'SNR (dB)'};
t.RowName        = {};
t.ColumnEditable = false(1, 4);
t.Data           = cell(0, 4);
obj.handles.BandsTable = t;
end


function build_sound_level_tab_(obj, tg, tip)
% What a sound level meter would read: the time-weighted level against time,
% over a table of every weighting and every readout.
tab = uitab(tg, 'Title', 'Sound Level');

tgrid = uigridlayout(tab);
tgrid.ColumnWidth = {80, 90, 110, 110, '1x'};
tgrid.RowHeight   = {24, '1x', 22, 240};   % nine readout rows without scrolling
tgrid.Padding     = [6 6 6 6];

lbl = uilabel(tgrid, 'Text', 'Weighting:', 'HorizontalAlignment', 'right');
lbl.Layout.Row    = 1;
lbl.Layout.Column = 1;

d = uidropdown(tgrid);
d.Items     = {'A', 'C', 'Z (none)'};
d.ItemsData = {"A", "C", "Z"};
d.Value     = "A";
d.Layout.Row    = 1;
d.Layout.Column = 2;
d.Tooltip   = tip('HistoryWeightingDD');
d.ValueChangedFcn = @(~,~) obj.update_plots_(obj.Metrics);
obj.handles.HistoryWeightingDD = d;

lbl = uilabel(tgrid, 'Text', 'Time weighting:', 'HorizontalAlignment', 'right');
lbl.Layout.Row    = 1;
lbl.Layout.Column = 3;

d = uidropdown(tgrid);
d.Items     = {'Fast (125 ms)', 'Slow (1 s)'};
d.ItemsData = {"F", "S"};
d.Value     = "F";
d.Layout.Row    = 1;
d.Layout.Column = 4;
d.Tooltip   = tip('TimeWeightingDD');
d.ValueChangedFcn = @(~,~) obj.update_plots_(obj.Metrics);
obj.handles.TimeWeightingDD = d;

ax = uiaxes(tgrid);
ax.Layout.Row    = 2;
ax.Layout.Column = [1 5];
grid(ax, 'on');
box(ax, 'on');
title(ax, 'Time-Weighted Level');
xlabel(ax, 'time (ms)');
ylabel(ax, 'level (dB)');
obj.handles.AxLevelHistory = ax;

lbl = uilabel(tgrid, 'Text', '', 'FontColor', [0.35 0.35 0.35]);
lbl.Layout.Row    = 3;
lbl.Layout.Column = [1 5];
lbl.Tooltip       = tip('LevelTable');
obj.handles.LevelNote = lbl;

t = uitable(tgrid);
t.Layout.Row     = 4;
t.Layout.Column  = [1 5];
t.ColumnName     = {'Readout', 'Z', 'A', 'C'};
t.RowName        = {};
t.ColumnEditable = false(1, 4);
t.Data           = cell(0, 4);
t.Tooltip        = tip('LevelTable');
obj.handles.LevelTable = t;
end
