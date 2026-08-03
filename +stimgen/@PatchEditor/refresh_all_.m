function refresh_all_(obj)
% refresh_all_(obj)
% Recompute geometry and redraw everything after a change to the patch.

if obj.closing || isempty(obj.fig) || ~isvalid(obj.fig)
    return
end

% A node may have been removed out from under the selection.
if obj.selKind == "node" && obj.selIdx > numel(obj.Patch.Graph.Nodes)
    obj.selKind = ""; obj.selIdx = 0;
elseif obj.selKind == "conn" && obj.selIdx > numel(obj.Patch.Graph.Connections)
    obj.selKind = ""; obj.selIdx = 0;
end

obj.geom = stimgen.PatchEditor.node_geometry_for_(obj.Patch);
obj.redraw_canvas_();
obj.build_inspector_();
obj.update_preview_();
obj.update_output_();
end
