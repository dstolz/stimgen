function build_ui_(obj)
% build_ui_(obj) - Build the StimInspector uifigure and all UI components.
%
% Layout: a header line across the top, an information column on the left
% (metrics table over parameter table), a tab group of plots on the right,
% and a status line along the bottom.

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
h = uilabel(g, 'Text', 'No stimulus selected.', ...
    'FontWeight', 'bold', 'FontSize', 13);
h.Layout.Row    = 1;
h.Layout.Column = [1 2];
obj.handles.HeaderLabel = h;

% ---- Left: information column ----
infoG = uigridlayout(g);
infoG.Layout.Row    = 2;
infoG.Layout.Column = 1;
infoG.ColumnWidth   = {'1x'};
infoG.RowHeight     = {'3x', '2x'};
infoG.Padding       = [0 0 0 0];
infoG.RowSpacing    = 6;

obj.handles.MetricsTable = make_table_(infoG, 1, 'Signal Metrics', {'Metric', 'Value'});
obj.handles.ParamsTable  = make_table_(infoG, 2, 'Parameters',     {'Parameter', 'Value'});

% ---- Right: plot tabs ----
tg = uitabgroup(g);
tg.Layout.Row    = 2;
tg.Layout.Column = 2;
% Only the visible tab is drawn, so a tab has to be brought up to date as it
% is selected (see update_plots_).
tg.SelectionChangedFcn = @(~,~) obj.update_plots_(obj.Metrics);
obj.handles.TabGroup = tg;

build_waveform_tab_(obj, tg);
build_spectrum_tab_(obj, tg);
build_spectrogram_tab_(obj, tg);
build_distortion_tab_(obj, tg);

% ---- Status line ----
h = uilabel(g, 'Text', 'Ready.', 'HorizontalAlignment', 'left', ...
    'FontColor', [0.35 0.35 0.35]);
h.Layout.Row    = 3;
h.Layout.Column = [1 2];
obj.handles.StatusLabel = h;

% ---- Toolbar ----
tb = uitoolbar(f);

obj.handles.RefreshTool = uipushtool(tb, 'Tooltip', 'Recompute From Stimulus', ...
    'Icon', stimgen.util.toolbar_icon('refresh'), ...
    'ClickedCallback', @(~,~) obj.refresh());

obj.handles.PlayTool = uipushtool(tb, 'Tooltip', 'Play Displayed Signal', 'Separator', 'on', ...
    'Icon', stimgen.util.toolbar_icon('play'), ...
    'ClickedCallback', @(~,~) obj.play_());

obj.handles.ExportTool = uipushtool(tb, 'Tooltip', 'Export Signal and Metrics to Workspace', ...
    'Icon', stimgen.util.toolbar_icon('save'), ...
    'ClickedCallback', @(~,~) obj.export_());

movegui(f, 'onscreen');
end % build_ui_


% =========================================================================
% Inline helpers called only from build_ui_
% =========================================================================

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


function build_spectrum_tab_(obj, tg)
% Magnitude-spectrum tab with axis-scale and harmonic-marker options.
tab = uitab(tg, 'Title', 'Spectrum');

tgrid = uigridlayout(tab);
tgrid.ColumnWidth = {150, 150, '1x'};
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

ax = uiaxes(tgrid);
ax.Layout.Row    = 2;
ax.Layout.Column = [1 3];
grid(ax, 'on');
box(ax, 'on');
title(ax, 'Magnitude Spectrum');
xlabel(ax, 'frequency (Hz)');
ylabel(ax, 'magnitude (dB re full scale)');
obj.handles.AxSpectrum = ax;
end


function build_spectrogram_tab_(obj, tg)
% Spectrogram tab with a selectable FFT length.
tab = uitab(tg, 'Title', 'Spectrogram');

tgrid = uigridlayout(tab);
tgrid.ColumnWidth = {90, 110, '1x'};
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

ax = uiaxes(tgrid);
ax.Layout.Row    = 2;
ax.Layout.Column = [1 3];
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
t.ColumnName     = {'Harmonic', 'Frequency (Hz)', 'Level (dB re F0)', 'Amplitude (%)'};
t.RowName        = {};
t.ColumnEditable = false(1, 4);
t.Data           = cell(0, 4);
obj.handles.HarmonicsTable = t;
end
