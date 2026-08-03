function build_ui_(obj)
% build_ui_(obj)
% Construct the editor window: palette, canvas, inspector, preview.

obj.fig = uifigure('Name', 'Patch Editor', ...
    'Position', [100 100 1180 720], ...
    'CloseRequestFcn', @(~,~) obj.close_request_());

g = uigridlayout(obj.fig, [3 3]);
g.RowHeight   = {'1x', 165, 24};
g.ColumnWidth = {170, '1x', 260};
g.Padding     = [8 8 8 8];

% ---------------- Palette ----------------
pal = uipanel(g, 'Title', 'Components');
pal.Layout.Row = [1 2];
pal.Layout.Column = 1;
pg = uigridlayout(pal, [4 1]);
pg.RowHeight = {'1x', 30, 30, 30};

[kinds, descs] = stimgen.components.list();
obj.h.KindList = uilistbox(pg, 'Items', cellstr(kinds), 'Value', char(kinds(1)));
obj.h.KindList.Tooltip = cellstr(descs);

obj.h.AddBtn = uibutton(pg, 'Text', 'Add Node', ...
    'ButtonPushedFcn', @(~,~) obj.add_node_ui_());
obj.h.DelBtn = uibutton(pg, 'Text', 'Delete Selected', ...
    'ButtonPushedFcn', @(~,~) obj.delete_selection_());
obj.h.LayoutBtn = uibutton(pg, 'Text', 'Auto Layout', ...
    'Tooltip', 'Arrange nodes left to right by graph depth', ...
    'ButtonPushedFcn', @(~,~) obj.auto_layout_());

% ---------------- Canvas ----------------
canvasPanel = uipanel(g, 'Title', 'Signal Graph');
canvasPanel.Layout.Row = 1;
canvasPanel.Layout.Column = 2;

obj.ax = uiaxes(canvasPanel, 'Units', 'normalized', 'Position', [0 0 1 1]);
obj.ax.XLim = [0 1];
obj.ax.YLim = [0 1];
obj.ax.XTick = [];
obj.ax.YTick = [];
obj.ax.Box = 'on';
obj.ax.Color = [0.97 0.97 0.98];
obj.ax.XColor = 'none';
obj.ax.YColor = 'none';

% Default axes interactions would swallow the drags this editor is built on:
% pan/zoom claim the mouse before any ButtonDownFcn runs.
disableDefaultInteractivity(obj.ax);
obj.ax.Interactions   = [];
obj.ax.Toolbar.Visible = 'off';
obj.ax.HitTest        = 'on';
obj.ax.PickableParts  = 'all';

% Drags are driven from the FIGURE rather than from per-object callbacks:
% hit testing against stored geometry in data units is far more predictable
% inside a uiaxes than relying on which primitive MATLAB decides was picked.
obj.fig.WindowButtonDownFcn   = @obj.on_mouse_down_;
obj.fig.WindowButtonMotionFcn = @obj.on_mouse_move_;
obj.fig.WindowButtonUpFcn     = @obj.on_mouse_up_;
obj.fig.KeyPressFcn           = @obj.on_key_;

% ---------------- Inspector ----------------
insp = uipanel(g, 'Title', 'Inspector');
insp.Layout.Row = [1 2];
insp.Layout.Column = 3;
obj.h.InspectorPanel = insp;

% ---------------- Preview ----------------
prev = uipanel(g, 'Title', 'Preview');
prev.Layout.Row = 2;
prev.Layout.Column = 2;
obj.h.PreviewAx = uiaxes(prev, 'Units', 'normalized', 'Position', [0 0 1 1]);
disableDefaultInteractivity(obj.h.PreviewAx);
obj.h.PreviewAx.Toolbar.Visible = 'off';

% ---------------- Status bar ----------------
bar = uigridlayout(g, [1 4]);
bar.Layout.Row = 3;
bar.Layout.Column = [1 3];
bar.ColumnWidth = {110, '1x', 90, 90};
bar.Padding = [0 0 0 0];

obj.h.PresetDD = uidropdown(bar, ...
    'Items', [{'Preset...'} cellstr(stimgen.Patch.preset_names())], ...
    'Value', 'Preset...', ...
    'ValueChangedFcn', @(s,~) obj.apply_preset_(s.Value));

obj.h.Status = uilabel(bar, 'Text', '', 'FontColor', [0.25 0.25 0.3]);

uibutton(bar, 'Text', 'Revert', 'ButtonPushedFcn', @(~,~) obj.revert_());
uibutton(bar, 'Text', 'Close',  'ButtonPushedFcn', @(~,~) obj.close_request_());

obj.set_status_("Drag an output port to an input port to connect. " + ...
    "Drag to OUT to choose the stimulus signal.", "info");
end
