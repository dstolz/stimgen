function on_mouse_down_(obj, ~, ~)
% on_mouse_down_(obj) - Begin a drag, or change the selection.

if obj.closing, return, end

pt = obj.canvas_point_();
if isempty(pt), return, end

hit = obj.hit_test_(pt);

switch hit.Kind
    case "outport"
        obj.dragMode  = "wire";
        obj.dragIdx   = hit.Idx;
        obj.dragPoint = pt;
        obj.set_status_("Release on an input port to connect, or on OUT to " + ...
            "make this the stimulus signal.", "info");

    case "node"
        obj.dragMode = "node";
        obj.dragIdx  = hit.Idx;
        obj.dragOff  = [obj.geom(hit.Idx).X - pt(1), obj.geom(hit.Idx).Y - pt(2)];
        obj.dragPos  = [obj.geom(hit.Idx).X, obj.geom(hit.Idx).Y];
        obj.selKind  = "node";
        obj.selIdx   = hit.Idx;
        obj.build_inspector_();
        obj.update_preview_();

    case "inport"
        obj.selKind = "node";
        obj.selIdx  = hit.Idx;
        obj.build_inspector_();
        obj.update_preview_();

    case "conn"
        obj.selKind = "conn";
        obj.selIdx  = hit.Idx;
        obj.build_inspector_();

    otherwise
        obj.selKind = "";
        obj.selIdx  = 0;
        obj.build_inspector_();
        obj.update_preview_();
end

obj.redraw_canvas_();
end
