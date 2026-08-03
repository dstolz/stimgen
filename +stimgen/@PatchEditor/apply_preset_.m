function apply_preset_(obj, name)
% apply_preset_(obj, name)
% Replace the current graph with a named preset.
%
% Only the graph is taken from the preset. Duration, level, gating and
% calibration settings belong to the stimulus the user is editing and are left
% alone.

obj.h.PresetDD.Value = 'Preset...';   % the dropdown is an action, not a state

if strcmp(name, 'Preset...')
    return
end

try
    src = stimgen.Patch.preset(name);

    obj.Patch.Graph      = src.Graph;
    obj.Patch.OutputNode = src.OutputNode;

    for prop = src.UserProperties
        p = char(prop);
        if prop == "Graph" || prop == "OutputNode", continue, end
        if isprop(src, p) && isprop(obj.Patch, p) && startsWith(prop, src.node_labels() + "_")
            obj.Patch.(p) = src.(p);
        end
    end

    obj.selKind = ""; obj.selIdx = 0;
    obj.set_status_("Loaded preset """ + string(name) + """.", "info");
catch ME
    obj.set_status_(ME.message, "error");
end

obj.refresh_all_();
end
