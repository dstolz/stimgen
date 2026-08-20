function build_ui_(obj)
% build_ui_(obj) - Build the SpotCheck uifigure and all its components.
%
% Layout: a header line across the top, a control and result column on the
% left, the two pair-comparison plots on the right, a status line along the
% bottom.
%
% Only two plots are drawn here, and both are of the PAIR: the stimulus and
% the recording overlaid on one time base, and their two spectra on one
% frequency axis. Everything about either signal on its own belongs in a
% stimgen.StimInspector window, which the toolbar opens, and duplicating the
% inspector's four tabs here would leave two copies of the same analysis to
% keep in step.

f = uifigure('Name', 'Stimulus Spot Check', 'Position', [160 110 1180 780]);
f.DeleteFcn = @(~,~) delete(obj);
obj.Figure = f;

g = uigridlayout(f);
g.ColumnWidth = {370, '1x'};
g.RowHeight   = {30, '1x', 22};
g.Padding     = [6 6 6 6];
g.RowSpacing  = 4;
g.ColumnSpacing = 6;

% ---- Header ----
h = uilabel(g, 'Text', 'No stimulus loaded.', ...
    'FontWeight', 'bold', 'FontSize', 13);
h.Layout.Row    = 1;
h.Layout.Column = [1 2];
obj.handles.HeaderLabel = h;

% ---- Left: controls over results ----
leftG = uigridlayout(g);
leftG.Layout.Row    = 2;
leftG.Layout.Column = 1;
leftG.ColumnWidth   = {'1x'};
leftG.RowHeight     = {112, 150, '1x'};
leftG.Padding       = [0 0 0 0];
leftG.RowSpacing    = 6;

build_stimulus_panel_(obj, leftG);
build_capture_panel_(obj, leftG);
build_results_panel_(obj, leftG);

% ---- Right: the two comparison plots ----
rightG = uigridlayout(g);
rightG.Layout.Row    = 2;
rightG.Layout.Column = 2;
rightG.ColumnWidth   = {'1x'};
rightG.RowHeight     = {'1x', '1x', '1.5x'};
rightG.Padding       = [0 0 0 0];
rightG.RowSpacing    = 4;

% The two waveforms get an axes each rather than one shared axes. Overlaid,
% they are two full-scale traces of the same length: for anything but a very
% short stimulus each decimates into a solid block and the one drawn first
% disappears entirely under the other. Stacked with a linked time axis, the
% comparison a spot check is for -- same envelope? same gate? cut in the right
% place? -- is read vertically, and neither trace hides the other.
ax = uiaxes(rightG);
ax.Layout.Row = 1;
grid(ax, 'on'); box(ax, 'on');
title(ax, 'Stimulus');
ylabel(ax, 'normalized');
obj.handles.AxStim = ax;

ax = uiaxes(rightG);
ax.Layout.Row = 2;
grid(ax, 'on'); box(ax, 'on');
title(ax, 'Recording');
xlabel(ax, 'time (ms)');
ylabel(ax, 'normalized');
obj.handles.AxRec = ax;

ax = uiaxes(rightG);
ax.Layout.Row = 3;
grid(ax, 'on'); box(ax, 'on');
title(ax, 'Spectra');
xlabel(ax, 'frequency (Hz)');
ylabel(ax, 'magnitude (dB re peak)');
obj.handles.AxSpectrum = ax;

% ---- Status line ----
h = uilabel(g, 'Text', 'Load a stimulus to spot check.', ...
    'HorizontalAlignment', 'left', 'FontColor', [0.35 0.35 0.35]);
h.Layout.Row    = 3;
h.Layout.Column = [1 2];
obj.handles.StatusLabel = h;

build_toolbar_(obj, f);

movegui(f, 'onscreen');
end % build_ui_


% =========================================================================

function build_stimulus_panel_(obj, parent)
% What is loaded, where it came from, and the two actions that change it.

pnl = uipanel(parent, 'Title', 'Stimulus', 'FontWeight', 'bold');
pnl.Layout.Row = 1;

pg = uigridlayout(pnl);
pg.ColumnWidth = {'1x', 'fit'};
pg.RowHeight   = {'1x', 24};
pg.Padding     = [6 4 6 4];
pg.RowSpacing  = 4;

lbl = uilabel(pg, 'Text', 'No stimulus loaded.', ...
    'VerticalAlignment', 'top', 'WordWrap', 'on');
lbl.Layout.Row    = 1;
lbl.Layout.Column = [1 2];
obj.handles.StimLabel = lbl;

b = uibutton(pg, 'Text', 'Load Stimulus...', ...
    'Tooltip', tip_('LoadBtn'), ...
    'ButtonPushedFcn', @(~,~) guarded_(obj, @() obj.load_stimulus()));
b.Layout.Row    = 2;
b.Layout.Column = 1;
obj.handles.LoadBtn = b;

b = uibutton(pg, 'Text', 'Match Rate', ...
    'Tooltip', tip_('MatchRateBtn'), ...
    'ButtonPushedFcn', @(~,~) guarded_(obj, @() obj.match_hardware_rate()));
b.Layout.Row    = 2;
b.Layout.Column = 2;
obj.handles.MatchRateBtn = b;
end


function build_capture_panel_(obj, parent)
% The three acquisition settings, and Run.

pnl = uipanel(parent, 'Title', 'Capture', 'FontWeight', 'bold');
pnl.Layout.Row = 2;

pg = uigridlayout(pnl);
pg.ColumnWidth = {110, 80, '1x'};
pg.RowHeight   = {24, 24, 24, 28};
pg.Padding     = [6 4 6 4];
pg.RowSpacing  = 3;

% Seconds in the object, milliseconds in the GUI -- the package-wide rule.
obj.handles.PreField = numeric_row_(pg, 1, 'Pre Delay (ms)', ...
    obj.PreDelay * 1e3, [0 10000], tip_('PreDelay'), ...
    @(src,~) guarded_(obj, @() set_time_(obj, 'PreDelay', src)));

obj.handles.PostField = numeric_row_(pg, 2, 'Post Delay (ms)', ...
    obj.PostDelay * 1e3, [0 10000], tip_('PostDelay'), ...
    @(src,~) guarded_(obj, @() set_time_(obj, 'PostDelay', src)));

obj.handles.RepeatsField = numeric_row_(pg, 3, 'Repeats', ...
    obj.Repeats, [1 100], tip_('Repeats'), ...
    @(src,~) guarded_(obj, @() set_repeats_(obj, src)));
obj.handles.RepeatsField.RoundFractionalValues = 'on';

b = uibutton(pg, 'Text', 'Run Spot Check', 'FontWeight', 'bold', ...
    'Tooltip', tip_('RunBtn'), ...
    'ButtonPushedFcn', @(~,~) run_clicked_(obj));
b.Layout.Row    = 4;
b.Layout.Column = [1 3];
obj.handles.RunBtn = b;
end


function build_results_panel_(obj, parent)
% The reduction, as a two-column table -- the same shape stimgen.StimInspector
% reports its metrics in, so the two windows read alike side by side.

pnl = uipanel(parent, 'Title', 'Result', 'FontWeight', 'bold');
pnl.Layout.Row = 3;

pg = uigridlayout(pnl);
pg.ColumnWidth = {'1x'};
pg.RowHeight   = {'1x'};
pg.Padding     = [2 2 2 2];

t = uitable(pg);
t.ColumnName     = {'Measure', 'Value'};
t.RowName        = {};
t.ColumnWidth    = {160, 'auto'};
t.ColumnEditable = [false false];
t.Data           = cell(0, 2);
obj.handles.ResultsTable = t;
end


function build_toolbar_(obj, f)
% Run, the two inspectors, save, help.

tb = uitoolbar(f);

obj.handles.OpenTool = uipushtool(tb, 'Tooltip', tip_('LoadBtn'), ...
    'Icon', stimgen.util.toolbar_icon('open'), ...
    'ClickedCallback', @(~,~) guarded_(obj, @() obj.load_stimulus()));

obj.handles.RunTool = uipushtool(tb, 'Tooltip', tip_('RunBtn'), 'Separator', 'on', ...
    'Icon', stimgen.util.toolbar_icon('play'), ...
    'ClickedCallback', @(~,~) run_clicked_(obj));

obj.handles.InspectCaptureTool = uipushtool(tb, 'Tooltip', tip_('InspectCaptureTool'), ...
    'Separator', 'on', ...
    'Icon', stimgen.util.toolbar_icon('inspect'), ...
    'ClickedCallback', @(~,~) guarded_(obj, @() obj.show_inspector("recording")));

obj.handles.InspectStimTool = uipushtool(tb, 'Tooltip', tip_('InspectStimTool'), ...
    'Icon', stimgen.util.toolbar_icon('transfer'), ...
    'ClickedCallback', @(~,~) guarded_(obj, @() obj.show_inspector("stimulus")));

obj.handles.SaveTool = uipushtool(tb, 'Tooltip', tip_('SaveTool'), 'Separator', 'on', ...
    'Icon', stimgen.util.toolbar_icon('save'), ...
    'ClickedCallback', @(~,~) guarded_(obj, @() obj.save_results()));

obj.handles.ShotTool = uipushtool(tb, 'Tooltip', tip_('ShotTool'), ...
    'Icon', stimgen.util.toolbar_icon('camera'), ...
    'ClickedCallback', @(~,~) guarded_(obj, @() obj.save_screenshot()));

obj.handles.SummaryTool = uipushtool(tb, 'Tooltip', tip_('SummaryTool'), ...
    'Icon', stimgen.util.toolbar_icon('summary'), ...
    'ClickedCallback', @(~,~) guarded_(obj, @() obj.describe()));

obj.handles.HelpTool = uipushtool(tb, 'Tooltip', tip_('HelpTool'), 'Separator', 'on', ...
    'Icon', stimgen.util.toolbar_icon('wiki'), ...
    'ClickedCallback', @(~,~) web(stimgen.SpotCheck.GuideURL, '-browser'));
end


% =========================================================================

function fld = numeric_row_(parent, row, labelText, value, limits, tipText, callback)
% One label + numeric edit field on a grid row.
lbl = uilabel(parent, 'Text', labelText, 'HorizontalAlignment', 'right', ...
    'Tooltip', tipText);
lbl.Layout.Row    = row;
lbl.Layout.Column = 1;

fld = uieditfield(parent, 'numeric', 'Value', value, 'Limits', limits, ...
    'Tooltip', tipText, 'ValueChangedFcn', callback);
fld.Layout.Row    = row;
fld.Layout.Column = 2;
end


function t = tip_(key)
% Hover text from the one catalog; never written out here.
t = stimgen.util.tooltip('SpotCheck', key);
end


function set_time_(obj, propName, src)
% A time field, milliseconds on screen back to seconds on the object.
obj.(propName) = src.Value / 1e3;
end


function set_repeats_(obj, src)
obj.Repeats = round(src.Value);
end


function run_clicked_(obj)
% Run, with the button disabled for the duration so a second press cannot
% queue a second acquisition behind the first.
if obj.is_running()
    obj.cancel();
    return
end
guarded_(obj, @() obj.run());
end


function guarded_(obj, fcn)
% Run a GUI action, turning any failure into a status line and a log entry
% rather than an uncaught error dialog. A spot check runs on hardware that
% fails in ordinary ways -- a device in use, a stimulus at the wrong rate --
% and none of those should look like a crash.
try
    fcn();
catch ME
    stimgen.util.vprintf(0, 1, 'SpotCheck: %s', ME.message);
    stimgen.util.vprintf(2, 1, ME);
    obj.set_status_(friendly_(ME), isError = true);
end
end


function msg = friendly_(ME)
% Guidance for the failures a user can actually act on, mirroring
% stimgen.StimPlayer.format_gui_error_message_.
switch ME.identifier
    case 'stimgen:SpotCheck:sampleRateMismatch'
        msg = string(ME.message) + " (the Match Rate button does this)";
    case {'stimgen:SpotCheck:noAdapter', 'stimgen:calibration:Engine:noAdapter'}
        msg = "No acquisition hardware is attached, so nothing can be " + ...
              "played or recorded. Attach an adapter first.";
    case 'stimgen:SpotCheck:noStimulus'
        msg = "Load a stimulus before running a spot check.";
    case 'stimgen:SpotCheck:noResults'
        msg = "Run a spot check before saving.";
    otherwise
        msg = string(ME.message);
end
end
