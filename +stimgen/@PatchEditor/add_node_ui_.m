function add_node_ui_(obj)
% add_node_ui_(obj)
% Add the component selected in the palette, at the first free canvas slot.

kind = string(obj.h.KindList.Value);

% Unique label: the kind's leading letters plus the next free number, which
% is what a person would type anyway (Osc1, Osc2, ...).
stem = local_stem(kind);
n = 1;
while any(obj.Patch.node_labels() == stem + string(n))
    n = n + 1;
end
label = stem + string(n);

try
    obj.Patch.add_node(label, kind);
    obj.Patch.set_node_position(label, local_free_slot(obj));
    obj.selKind = "node";
    obj.selIdx  = numel(obj.Patch.Graph.Nodes);
    obj.set_status_("Added " + label + " (" + kind + ").", "info");
catch ME
    obj.set_status_(ME.message, "error");
end

obj.refresh_all_();
end


function s = local_stem(kind)
switch kind
    case "Oscillator",  s = "Osc";
    case "NoiseSource", s = "Noise";
    case "PulseTrain",  s = "Pulse";
    case "Sweep",       s = "Sweep";
    case "Mixer",       s = "Mix";
    case "Constant",    s = "Const";
    case "FileSource",  s = "File";
    otherwise,          s = kind;
end
end

function pos = local_free_slot(obj)
% First grid slot not already occupied, so new nodes do not stack. The grid
% stays clear of the right edge, where the OUT terminal lives, and of the
% bottom, where a tall node would otherwise hang off the canvas.
occupied = reshape([obj.Patch.Graph.Nodes.Position], 2, []).';
for row = 0:2
    for col = 0:2
        pos = [0.05 + 0.24*col, 0.92 - 0.29*row];
        if isempty(occupied) || all(hypot(occupied(:,1)-pos(1), occupied(:,2)-pos(2)) > 0.05)
            return
        end
    end
end
pos = [0.05 + 0.55*rand, 0.40 + 0.50*rand];
end
