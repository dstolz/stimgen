function on_mouse_up_(obj, ~, ~)
% on_mouse_up_(obj) - Commit whatever was being dragged.

if obj.closing || obj.dragMode == "idle"
    return
end

mode = obj.dragMode;
idx  = obj.dragIdx;
pt   = obj.canvas_point_();

obj.dragMode = "idle";
obj.dragIdx  = 0;

try
    switch mode
        case "node"
            obj.Patch.set_node_position(obj.geom(idx).Label, obj.dragPos);

        case "wire"
            if isempty(pt)
                obj.refresh_all_();
                return
            end
            hit = obj.hit_test_(pt);
            from = obj.geom(idx).Label;

            switch hit.Kind
                case "inport"
                    to    = obj.geom(hit.Idx).Label;
                    param = obj.geom(hit.Idx).InNames(hit.Port);
                    if to == from
                        obj.set_status_("A node cannot modulate its own parameter.", "warn");
                    else
                        % "Direct" is what a Mixer input almost always wants;
                        % anything else is far more often an AM connection.
                        if startsWith(param, "In") && obj.geom(hit.Idx).Kind == "Mixer"
                            obj.Patch.add_connection(from, to, param, Mode = "Direct");
                        else
                            obj.Patch.add_connection(from, to, param, Mode = "AM", Depth = 1);
                        end
                        obj.set_status_(from + " -> " + to + "." + param + " connected.", "info");
                    end

                case "terminal"
                    obj.Patch.OutputNode = obj.geom(idx).Label;
                    obj.set_status_(obj.geom(idx).Label + " is now the stimulus output.", "info");
            end
    end
catch ME
    obj.set_status_(ME.message, "error");
end

obj.refresh_all_();
end
