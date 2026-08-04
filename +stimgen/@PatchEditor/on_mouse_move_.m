function on_mouse_move_(obj, ~, ~)
% on_mouse_move_(obj) - Track an in-progress drag.
%
% Nothing is written to the patch here: a node's committed Position and any
% new connection are applied on release. Dragging therefore never triggers a
% re-render, which keeps the canvas responsive.

if obj.closing || obj.dragMode == "idle"
    return
end

pt = obj.canvas_point_();
if isempty(pt), return, end

switch obj.dragMode
    case "node"
        pos = [pt(1) + obj.dragOff(1), pt(2) + obj.dragOff(2)];
        % Keep the whole box on the canvas.
        h = obj.geom(obj.dragIdx).H;
        pos(1) = min(max(pos(1), 0.005), 1 - obj.NODE_W - 0.06);
        pos(2) = min(max(pos(2), h + 0.005), 0.995);
        obj.dragPos = pos;
        % dragPos is only maintained during a node drag; rebuilding the
        % geometry with it in wire mode would teleport the wire's source
        % node to wherever the previous node drag ended.
        obj.geom = stimgen.PatchEditor.node_geometry_for_(obj.Patch, obj.dragIdx, obj.dragPos);

    case "wire"
        obj.dragPoint = pt;
end

obj.redraw_canvas_();
end
