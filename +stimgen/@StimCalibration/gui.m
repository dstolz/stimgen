function gui(obj)
% gui(obj)
% Build or re-use the StimCalibration window.
%
% Two columns: the engine parameters and run buttons on the left, and a
% stimgen.calibration.LiveMonitor on the right, whose three panels are attached
% to this figure's own axes rather than to a window of their own. That is what
% puts a sweep's progress next to the controls driving it -- previously the
% only thing this GUI showed was a waveform and a spectrum, in a detached
% figure, and only after a reference measurement, so the transfer curve the
% whole run exists to produce was never visible here at all.
%
% Registers a PostSet listener on STATE to drive the calibration state machine.

% Re-entry: a second gui() call must raise the existing window, not stack
% another toolbar and grid onto it.
if isfield(obj.handles, 'SideGrid') && ~isempty(obj.handles.SideGrid) ...
        && isvalid(obj.handles.SideGrid)
    f = ancestor(obj.handles.parent, 'figure');
    if ~isempty(f), figure(f); end
    return
end

if isempty(obj.handles.parent)
    h   = uifigure('Name', 'Stimulus Calibration');
    pos = getpref('StimCalibration', 'pos', [180 140 1200 680]);
    % A stored preference may remember the control-only window this GUI used
    % to be, which cannot hold the plot panel.
    pos(3) = max(pos(3), 980);
    pos(4) = max(pos(4), 600);
    h.Position = pos;
    h.CloseRequestFcn = @(src, ~) close_gui_(obj, src);
    obj.handles.parent = h;
end

parent = obj.handles.parent;
fig    = ancestor(parent, 'figure');
movegui(fig, 'onscreen');

% --- Toolbar ---
% Tool handles pick up the same Enable on/off sweep that calibration_state
% applies to the rest of the GUI (findobj(..., '-property', 'Enable')), so
% no separate enable/disable wiring is needed here.
tb = uitoolbar(fig);

tip = @(key) stimgen.util.tooltip('StimCalibration', key);

h = uipushtool(tb, 'Tooltip', tip('LoadTool'), ...
    'Icon', stimgen.util.toolbar_icon('open'), ...
    'ClickedCallback', @(~,~) obj.load_calibration());
obj.handles.MenuLoadCalibrationTool = h;

h = uipushtool(tb, 'Tooltip', tip('SaveTool'), ...
    'Icon', stimgen.util.toolbar_icon('save'), ...
    'ClickedCallback', @(~,~) obj.save_calibration());
obj.handles.MenuSaveCalibrationTool = h;

h = uipushtool(tb, 'Tooltip', tip('MeasureReferenceTool'), 'Separator', 'on', ...
    'Icon', stimgen.util.toolbar_icon('calibration'), ...
    'ClickedCallback', @obj.measure_ref);
obj.handles.RefMeasureTool = h;

h = uipushtool(tb, 'Tooltip', tip('RunCalibrationTool'), ...
    'Icon', stimgen.util.toolbar_icon('play'), ...
    'ClickedCallback', @obj.run_calibration);
obj.handles.RunCalibrationTool = h;

h = uipushtool(tb, 'Tooltip', tip('RefreshPlotsTool'), 'Separator', 'on', ...
    'Icon', stimgen.util.toolbar_icon('refresh'), ...
    'ClickedCallback', @(~,~) obj.refresh_plots());
obj.handles.RefreshPlotsTool = h;

% --- Root layout: controls | plots ---
root             = uigridlayout(parent, [1 2]);
root.ColumnWidth = {300, '1x'};
root.RowHeight   = {'1x'};
root.Padding     = [4 4 4 4];
obj.handles.RootGrid = root;

ctrl = uipanel(root, 'Title', 'Calibration');
ctrl.Layout.Row    = 1;
ctrl.Layout.Column = 1;

sg             = uigridlayout(ctrl, [11 2]);
sg.ColumnWidth = {'1x', '1x'};
sg.RowHeight   = [repmat({30}, 1, 3) {36} repmat({30}, 1, 3) {52} {26} {26} {'1x'}];
sg.Scrollable  = 'on';
obj.handles.SideGrid = sg;

R = 1;

% --- Ref. Sound Level ---
h = uilabel(sg);
h.Layout.Column = 1; h.Layout.Row = R;
h.Text = 'Ref. Sound Level:'; h.HorizontalAlignment = 'right';

h = uieditfield(sg, 'numeric');
h.Tag = 'ReferenceLevel';
h.Layout.Column = 2; h.Layout.Row = R;
h.ValueDisplayFormat = '%.1f dB SPL';
h.Value  = obj.Engine.ReferenceLevel;
h.Limits = [1 160];
h.ValueChangedFcn = @obj.set_prop;
obj.handles.ReferenceLevel = h;
R = R + 1;

% --- Ref. Frequency ---
h = uilabel(sg);
h.Layout.Column = 1; h.Layout.Row = R;
h.Text = 'Ref. Frequency:'; h.HorizontalAlignment = 'right';

h = uieditfield(sg, 'numeric');
h.Tag = 'ReferenceFrequency';
h.Layout.Column = 2; h.Layout.Row = R;
h.ValueDisplayFormat = '%.1f Hz';
h.Value  = obj.Engine.ReferenceFrequency;
h.Limits = [100 100000];
h.ValueChangedFcn = @obj.set_prop;
obj.handles.ReferenceFrequency = h;
R = R + 1;

% --- Mic Sensitivity ---
h = uilabel(sg);
h.Layout.Column = 1; h.Layout.Row = R;
h.Text = 'Mic. Sensitivity:'; h.HorizontalAlignment = 'right';

h = uieditfield(sg, 'numeric');
h.Tag = 'MicSensitivity';
h.Layout.Column = 2; h.Layout.Row = R;
h.ValueDisplayFormat = '%.4f V/Pa';
h.Limits = [0 10];
h.LowerLimitInclusive = 'off';
h.Value = obj.Engine.MicSensitivity;
h.ValueChangedFcn = @obj.set_prop;
obj.handles.MicSensitivity = h;
R = R + 1;

% --- Measure Reference button ---
h = uibutton(sg);
h.Layout.Column = [1 2]; h.Layout.Row = R;
h.Text = 'Measure Reference';
h.ButtonPushedFcn = @obj.measure_ref;
obj.handles.RefMeasure = h;
R = R + 1;

% --- Normative Sound Level ---
h = uilabel(sg);
h.Layout.Column = 1; h.Layout.Row = R;
h.Text = 'Normative Sound Level:'; h.HorizontalAlignment = 'right';

h = uieditfield(sg, 'numeric');
h.Tag = 'NormativeValue';
h.Layout.Column = 2; h.Layout.Row = R;
h.ValueDisplayFormat = '%d dB SPL';
h.Value  = obj.Engine.NormativeValue;
h.Limits = [60 120];
h.ValueChangedFcn = @obj.set_prop;
obj.handles.NormativeValue = h;
R = R + 1;

% --- Excitation Voltage ---
h = uilabel(sg);
h.Layout.Column = 1; h.Layout.Row = R;
h.Text = 'Excitation Voltage:'; h.HorizontalAlignment = 'right';

h = uieditfield(sg, 'numeric');
h.Tag = 'ExcitationSignalVoltage';
h.Layout.Column = 2; h.Layout.Row = R;
h.ValueDisplayFormat = '%.2f V';
h.Value  = obj.Engine.ExcitationVoltage;
h.Limits = [0 10];
h.LowerLimitInclusive = 'off';
h.ValueChangedFcn = @obj.set_prop;
obj.handles.ExcitationSignalVoltage = h;
R = R + 1;

% --- Max Output Voltage ---
% The ceiling the transfer panel draws its unreachable-level line at, and the
% full scale the clipping test is judged against.
h = uilabel(sg);
h.Layout.Column = 1; h.Layout.Row = R;
h.Text = 'Max Output Voltage:'; h.HorizontalAlignment = 'right';

h = uieditfield(sg, 'numeric');
h.Tag = 'MaxOutputVoltage';
h.Layout.Column = 2; h.Layout.Row = R;
h.ValueDisplayFormat = '%.2f V';
h.Value  = obj.Engine.MaxOutputVoltage;
h.Limits = [0 1000];
h.LowerLimitInclusive = 'off';
h.Tooltip = tip('MaxOutputVoltage');
h.ValueChangedFcn = @obj.set_prop;
obj.handles.MaxOutputVoltage = h;
R = R + 1;

% --- Run Calibration button ---
h = uibutton(sg);
h.Layout.Column = [1 2]; h.Layout.Row = R;
h.Text       = {'Run'; 'Calibration'};
h.FontSize   = 18;
h.FontWeight = 'bold';
h.ButtonPushedFcn = @obj.run_calibration;
obj.handles.RunCalibration = h;
R = R + 1;

% --- Live plots ---
h = uilabel(sg);
h.Layout.Column = 1; h.Layout.Row = R;
h.Text = 'Live Plots:'; h.HorizontalAlignment = 'right';

h = uicheckbox(sg, 'Text', '');
h.Layout.Column = 2; h.Layout.Row = R;
h.Value   = obj.Engine.ShowLivePlots;
h.Tooltip = tip('ShowLivePlots');
h.ValueChangedFcn = @(src,~) obj.Engine.set_configuration(ShowLivePlots=src.Value);
obj.handles.ShowLivePlots = h;
R = R + 1;

% --- Log x-axis ---
h = uilabel(sg);
h.Layout.Column = 1; h.Layout.Row = R;
h.Text = 'Log X-Axis:'; h.HorizontalAlignment = 'right';

h = uicheckbox(sg, 'Text', '');
h.Layout.Column = 2; h.Layout.Row = R;
h.Value   = true;
h.Tooltip = tip('LogXAxis');
h.ValueChangedFcn = @(src,~) obj.set_log_x_(src.Value);
obj.handles.LogXAxis = h;

% --- Plot panel ---
obj.build_plots_(root);

% --- File menu (.esgc) ---
hf = uimenu(fig, 'Text', '&File', 'Accelerator', 'F');

h = uimenu(hf, 'Tag', 'menu_Load', 'Text', '&Load (.esgc)', ...
    'Accelerator', 'L', ...
    'MenuSelectedFcn', @(~,~) obj.load_calibration());
obj.handles.MenuLoadCalibration = h;

h = uimenu(hf, 'Tag', 'menu_Save', 'Text', '&Save (.esgc)', ...
    'Accelerator', 'S', ...
    'Enable', 'off', ...
    'MenuSelectedFcn', @(~,~) obj.save_calibration());
obj.handles.MenuSaveCalibration = h;

% --- Activate state machine ---
obj.STATE = "IDLE";
addlistener(obj, 'STATE', 'PostSet', @obj.calibration_state);

obj.attach_engine_listeners_();
obj.refresh_plots();
end


% ------------------------------------------------------------------------ %
function close_gui_(obj, fig)
% Remember where the window was, release the monitor, then close.
%
% The monitor holds a listener on the engine. Left attached, it would keep
% rendering into deleted axes for the rest of the engine's life -- and the
% engine outlives this window, because a StimType keeps using it to convert
% levels long after the GUI is gone.
if isgraphics(fig)
    setpref('StimCalibration', 'pos', fig.Position);
end
if ~isempty(obj.Monitor) && isvalid(obj.Monitor)
    obj.Monitor.detach();
    delete(obj.Monitor);
end
delete(fig);
end
