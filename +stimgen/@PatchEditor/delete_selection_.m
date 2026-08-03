function delete_selection_(obj)
% delete_selection_(obj)
% Remove the selected node (and its connections) or the selected wire.

try
    switch obj.selKind
        case "node"
            label = obj.geom(obj.selIdx).Label;
            obj.Patch.remove_node(label);
            obj.set_status_("Removed " + label + ".", "info");

        case "conn"
            c = obj.Patch.Graph.Connections(obj.selIdx);
            obj.Patch.remove_connection(c.From, c.To, c.Param);
            obj.set_status_("Disconnected " + c.From + " -> " + c.To + "." + c.Param + ".", "info");

        otherwise
            obj.set_status_("Nothing selected.", "warn");
            return
    end
catch ME
    obj.set_status_(ME.message, "error");
end

obj.selKind = ""; obj.selIdx = 0;
obj.refresh_all_();
end
