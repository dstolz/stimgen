function i = node_index_(obj, label)
% i = node_index_(obj, label)
% Index of a node label in Graph.Nodes.

label = string(label);
i = find(obj.node_labels() == label, 1);
if isempty(i)
    labels = obj.node_labels();
    if isempty(labels)
        detail = "this patch has no nodes";
    else
        detail = "available nodes: " + strjoin(labels, ", ");
    end
    error('stimgen:Patch:UnknownNode', 'No node labelled "%s"; %s.', label, detail);
end
end
