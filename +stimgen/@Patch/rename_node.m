function rename_node(obj, oldLabel, newLabel)
% rename_node(obj, oldLabel, newLabel)
% Rename a node, carrying its parameter values and connections across.
%
% A node's label is part of every one of its parameter property names, so a
% rename would otherwise silently reset the node to defaults: rebuild_params_
% would see the old names disappear and the new ones appear. This reads the
% values first and writes them back under the new names.

oldLabel = string(oldLabel);
newLabel = string(newLabel);
if oldLabel == newLabel
    return
end

i = obj.node_index_(oldLabel);
if any(obj.node_labels() == newLabel)
    error('stimgen:Patch:DuplicateNodeLabel', ...
        'This patch already has a node labelled "%s".', newLabel);
end

% Capture the current values before the properties are torn down.
defs   = obj.components_{i}.param_defs();
names  = string(fieldnames(defs))';
values = cell(1, numel(names));
for k = 1:numel(names)
    values{k} = obj.(char(stimgen.Patch.flat_name_(oldLabel, names(k))));
end

g = obj.Graph;
g.Nodes(i).Label = newLabel;
for k = 1:numel(g.Connections)
    if g.Connections(k).From == oldLabel, g.Connections(k).From = newLabel; end
    if g.Connections(k).To   == oldLabel, g.Connections(k).To   = newLabel; end
end

wasOutput = obj.OutputNode == oldLabel;
obj.Graph = g;

for k = 1:numel(names)
    obj.(char(stimgen.Patch.flat_name_(newLabel, names(k)))) = values{k};
end

if wasOutput
    obj.OutputNode = newLabel;
end
end
