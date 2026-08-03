function redraw_canvas_(obj)
% redraw_canvas_(obj)
% Draw the whole graph: wires behind, then node boxes, then the OUT terminal.
%
% Everything is deleted and redrawn on each call. Patches hold at most a few
% dozen primitives, so this stays comfortably interactive even during a drag,
% and it removes a whole class of stale-handle bugs.

cla(obj.ax);
hold(obj.ax, 'on');
obj.ax.XLim = [0 1];
obj.ax.YLim = [0 1];

geom  = obj.geom;
conns = obj.Patch.Graph.Connections;
labels = obj.Patch.node_labels();

C.wire     = [0.45 0.48 0.55];
C.wireSel  = [0.10 0.45 0.85];
C.body     = [1.00 1.00 1.00];
C.edge     = [0.55 0.58 0.65];
C.edgeSel  = [0.10 0.45 0.85];
C.edgeOut  = [0.15 0.60 0.30];
C.port     = [0.55 0.58 0.65];
C.text     = [0.15 0.15 0.20];

% ---------------- Wires ----------------
for k = 1:numel(conns)
    s = find(labels == conns(k).From, 1);
    t = find(labels == conns(k).To,   1);
    if isempty(s) || isempty(t), continue, end

    p1 = geom(s).OutXY;
    pk = find(geom(t).InNames == conns(k).Param, 1);
    if isempty(pk), continue, end
    p2 = geom(t).InXY(pk,:);

    sel = obj.selKind == "conn" && obj.selIdx == k;
    if sel, col = C.wireSel; lw = 2.4; else, col = C.wire; lw = 1.4; end

    [wx, wy] = stimgen.PatchEditor.wire_path_(p1, p2);
    plot(obj.ax, wx, wy, '-', 'Color', col, 'LineWidth', lw, 'HitTest', 'off');

    % Mode label near the target end, so the routing reads without clicking.
    % An opaque background is what makes it legible where wires cross.
    at  = round(0.72 * numel(wx));
    txt = conns(k).Mode;
    if conns(k).Mode ~= "Direct"
        txt = txt + " " + local_num(conns(k).Depth);
    end
    text(obj.ax, wx(at), wy(at), txt, ...
        'FontSize', 7, 'Color', col, ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
        'BackgroundColor', [1 1 1], 'Margin', 1, ...
        'Interpreter', 'none', 'HitTest', 'off');
end

% In-progress wire drag
if obj.dragMode == "wire" && obj.dragIdx > 0
    [wx, wy] = stimgen.PatchEditor.wire_path_(geom(obj.dragIdx).OutXY, obj.dragPoint);
    plot(obj.ax, wx, wy, '--', 'Color', C.wireSel, 'LineWidth', 1.6, 'HitTest', 'off');
end

% ---------------- Nodes ----------------
for i = 1:numel(geom)
    n = geom(i);
    isSel = obj.selKind == "node" && obj.selIdx == i;
    isOut = obj.Patch.OutputNode == n.Label;

    if isSel
        ec = C.edgeSel; lw = 2.0;
    elseif isOut
        ec = C.edgeOut; lw = 1.8;
    else
        ec = C.edge;    lw = 1.0;
    end

    rectangle(obj.ax, 'Position', [n.X, n.Y - n.H, n.W, n.H], ...
        'Curvature', 0.10, 'FaceColor', C.body, 'EdgeColor', ec, ...
        'LineWidth', lw, 'HitTest', 'off');

    rectangle(obj.ax, 'Position', [n.X, n.Y - obj.HEAD_H, n.W, obj.HEAD_H], ...
        'Curvature', 0.10, 'FaceColor', local_kind_color(n.Kind), ...
        'EdgeColor', ec, 'LineWidth', lw, 'HitTest', 'off');

    text(obj.ax, n.X + 0.008, n.Y - obj.HEAD_H/2, n.Label, ...
        'FontSize', 8.5, 'FontWeight', 'bold', 'Color', C.text, ...
        'VerticalAlignment', 'middle', 'Interpreter', 'none', 'HitTest', 'off');
    text(obj.ax, n.X + n.W - 0.008, n.Y - obj.HEAD_H/2, n.Kind, ...
        'FontSize', 6.5, 'Color', [0.35 0.35 0.4], 'HorizontalAlignment', 'right', ...
        'VerticalAlignment', 'middle', 'Interpreter', 'none', 'HitTest', 'off');

    % Input ports
    for k = 1:numel(n.InNames)
        xy = n.InXY(k,:);
        local_port(obj.ax, xy, C.port);
        text(obj.ax, xy(1) + 0.014, xy(2), n.InNames(k), ...
            'FontSize', 7, 'Color', C.text, 'VerticalAlignment', 'middle', ...
            'Interpreter', 'none', 'HitTest', 'off');
    end

    % Output port
    local_port(obj.ax, n.OutXY, C.edgeOut);
end

% ---------------- OUT terminal ----------------
outY = 0.5;
local_port(obj.ax, [obj.OUT_X, outY], C.edgeOut);
text(obj.ax, obj.OUT_X, outY - 0.045, 'OUT', ...
    'FontSize', 8, 'FontWeight', 'bold', 'Color', C.edgeOut, ...
    'HorizontalAlignment', 'center', 'Interpreter', 'none', 'HitTest', 'off');

% Wire from the current output node to the terminal
oi = find(labels == obj.Patch.OutputNode, 1);
if ~isempty(oi)
    [wx, wy] = stimgen.PatchEditor.wire_path_(geom(oi).OutXY, [obj.OUT_X, outY]);
    plot(obj.ax, wx, wy, '-', 'Color', C.edgeOut, 'LineWidth', 2.0, 'HitTest', 'off');
end

hold(obj.ax, 'off');
end


% =========================================================================

function local_port(ax, xy, col)
r = 0.009;
rectangle(ax, 'Position', [xy(1)-r, xy(2)-r, 2*r, 2*r], ...
    'Curvature', 1, 'FaceColor', col, 'EdgeColor', 'none', 'HitTest', 'off');
end

function c = local_kind_color(kind)
switch kind
    case "Oscillator",  c = [0.83 0.90 1.00];
    case "NoiseSource", c = [0.88 0.88 0.92];
    case "PulseTrain",  c = [0.99 0.92 0.80];
    case "Sweep",       c = [0.86 0.95 0.88];
    case "Mixer",       c = [0.95 0.87 0.95];
    case "Constant",    c = [0.93 0.93 0.85];
    case "FileSource",  c = [0.85 0.94 0.96];
    otherwise,          c = [0.90 0.90 0.90];
end
end

function s = local_num(v)
s = string(num2str(v, '%g'));
end
