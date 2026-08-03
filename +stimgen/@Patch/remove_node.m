function remove_node(obj, label)
% remove_node(obj, label)
% Remove a node and every connection that touches it.
%
% If the removed node was the output node, rebuild_params_ falls back to the
% last remaining node so the patch keeps rendering rather than erroring on
% every subsequent update.

label = string(label);
i     = obj.node_index_(label);

g = obj.Graph;
g.Nodes(i) = [];
if ~isempty(g.Connections)
    drop = string({g.Connections.From}) == label | string({g.Connections.To}) == label;
    g.Connections(drop) = [];
end
obj.Graph = g;
end
