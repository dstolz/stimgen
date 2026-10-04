function [vals, ok, raw] = parameter_dialog_(parent, titleText, introText, specs, check)
% [vals, ok, raw] = parameter_dialog_(parent, titleText, introText, specs)
% [vals, ok, raw] = parameter_dialog_(parent, titleText, introText, specs, check)
% Modal window of typed fields; blocks until OK (with every field valid) or
% Cancel/Escape/close.
%
% Returns:
%   vals - struct, one field per spec key, validated (Validate's output)
%   ok   - false when cancelled
%   raw  - struct of each field's raw widget value, for preferences that
%          store what was typed (a list expression) rather than its value
arguments
    parent
    titleText (1,:) char
    introText (1,:) char
    specs (1,:) struct
    check = []
end
vals = struct();
raw  = struct();
ok   = false;

n = numel(specs);
hasIntro = ~isempty(introText);
heights = {};
if hasIntro
    heights{end+1} = 64;
end
heights = [heights, repmat({24}, 1, n), {36}, {26}];
w = 520;
h = 16 + sum(cellfun(@double, heights)) + 4 * (numel(heights) - 1);
pos = [100 100 w h];
if ~isempty(parent) && isvalid(parent)
    p = parent.Position;
    pos(1:2) = [p(1) + (p(3) - w) / 2, p(2) + (p(4) - h) / 2];
end

fig = uifigure(Name=titleText, Position=pos, Resize='off', WindowStyle='modal');
fig.CloseRequestFcn = @(~,~) finish_dialog_(fig, false);
fig.WindowKeyPressFcn = @(~,evt) dialog_key_(fig, evt);

g = uigridlayout(fig, [numel(heights) 2]);
g.RowHeight = heights;
g.ColumnWidth = {'1.25x', '1x'};
g.Padding = [8 8 8 8];
g.RowSpacing = 4;
g.ColumnSpacing = 8;

row = 0;
if hasIntro
    row = row + 1;
    intro = uilabel(g, Text=introText, WordWrap='on');
    intro.Layout.Row = row;
    intro.Layout.Column = [1 2];
end

widgets = cell(1, n);
for k = 1:n
    sp = specs(k);
    row = row + 1;
    lbl = uilabel(g, Text=char(sp.label), HorizontalAlignment='right');
    lbl.Layout.Row = row;
    lbl.Layout.Column = 1;
    switch sp.kind
        case {"numeric", "integer"}
            wdg = uieditfield(g, 'numeric', Limits=sp.limits, ...
                ValueDisplayFormat=sp.format);
            if sp.lowerOpen
                wdg.LowerLimitInclusive = 'off';
            end
            if sp.kind == "integer"
                wdg.RoundFractionalValues = 'on';
            end
            wdg.Value = double(sp.value);
        case "text"
            wdg = uieditfield(g, 'text', Value=char(string(sp.value)));
        case "dropdown"
            wdg = uidropdown(g, Items=cellstr(sp.items), ...
                ItemsData=cellstr(sp.items), Value=char(string(sp.value)));
    end
    wdg.Layout.Row = row;
    wdg.Layout.Column = 2;
    if ~isempty(sp.tip)
        lbl.Tooltip = sp.tip;
        wdg.Tooltip = sp.tip;
    end
    widgets{k} = wdg;
end

row = row + 1;
errLbl = uilabel(g, Text='', FontColor=[0.7 0 0], WordWrap='on');
errLbl.Layout.Row = row;
errLbl.Layout.Column = [1 2];

row = row + 1;
btns = uigridlayout(g, [1 2]);
btns.Layout.Row = row;
btns.Layout.Column = 2;
btns.Padding = [0 0 0 0];
btns.ColumnSpacing = 8;
okBtn = uibutton(btns, Text='OK', ...
    Tooltip=stimgen.util.tooltip('CalibrationGui', 'DlgOk'), ...
    ButtonPushedFcn=@(~,~) accept_dialog_(fig, specs, widgets, errLbl, check));
okBtn.Layout.Column = 1;
cancelBtn = uibutton(btns, Text='Cancel', ...
    Tooltip=stimgen.util.tooltip('CalibrationGui', 'DlgCancel'), ...
    ButtonPushedFcn=@(~,~) finish_dialog_(fig, false));
cancelBtn.Layout.Column = 2;

uiwait(fig);

if isvalid(fig)
    d = fig.UserData;
    delete(fig);
    if isstruct(d) && isfield(d, 'ok') && d.ok
        ok   = true;
        vals = d.vals;
        raw  = d.raw;
    end
end
end
