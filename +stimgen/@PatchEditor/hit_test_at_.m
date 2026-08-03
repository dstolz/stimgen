function hit = hit_test_at_(geom, graph, pt)
% hit = stimgen.PatchEditor.hit_test_at_(geom, graph, pt)
% Identify what lies under a canvas point.
%
% Tested against the same geometry the canvas was drawn from, in data units,
% rather than relying on MATLAB's picking inside a uiaxes -- which is
% unpredictable once objects overlap and default interactions are disabled.
%
% Pure and static, so hit testing can be verified without opening a window.
%
% Returns a struct with:
%   Kind  - "none" | "outport" | "inport" | "node" | "conn" | "terminal"
%   Idx   - node or connection index
%   Port  - input port index, for Kind == "inport"

hit = struct('Kind', "none", 'Idx', 0, 'Port', 0);

% Ports first: they sit on the node boundary and must win over the body.
tol = stimgen.PatchEditor.PORT_R * 2.2;

if hypot(pt(1) - stimgen.PatchEditor.OUT_X, pt(2) - 0.5) < tol
    hit.Kind = "terminal";
    return
end

for i = 1:numel(geom)
    if hypot(pt(1) - geom(i).OutXY(1), pt(2) - geom(i).OutXY(2)) < tol
        hit.Kind = "outport"; hit.Idx = i;
        return
    end
    for k = 1:size(geom(i).InXY, 1)
        if hypot(pt(1) - geom(i).InXY(k,1), pt(2) - geom(i).InXY(k,2)) < tol
            hit.Kind = "inport"; hit.Idx = i; hit.Port = k;
            return
        end
    end
end

% Node bodies, last drawn tested first so the topmost wins.
for i = numel(geom):-1:1
    n = geom(i);
    if pt(1) >= n.X && pt(1) <= n.X + n.W && pt(2) <= n.Y && pt(2) >= n.Y - n.H
        hit.Kind = "node"; hit.Idx = i;
        return
    end
end

% Wires: closest approach to the drawn polyline.
if isempty(geom)
    return
end
labels = string({geom.Label});
best   = inf;
bestK  = 0;
for k = 1:numel(graph.Connections)
    s = find(labels == graph.Connections(k).From, 1);
    t = find(labels == graph.Connections(k).To,   1);
    if isempty(s) || isempty(t), continue, end
    pk = find(geom(t).InNames == graph.Connections(k).Param, 1);
    if isempty(pk), continue, end

    [wx, wy] = stimgen.PatchEditor.wire_path_(geom(s).OutXY, geom(t).InXY(pk,:));
    d = min(hypot(wx - pt(1), wy - pt(2)));
    if d < best
        best  = d;
        bestK = k;
    end
end
if bestK > 0 && best < 0.015
    hit.Kind = "conn"; hit.Idx = bestK;
end
end
