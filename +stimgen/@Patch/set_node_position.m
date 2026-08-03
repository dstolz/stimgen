function set_node_position(obj, label, pos)
% set_node_position(obj, label, pos)
% Move a node on the patch editor canvas. pos is [x y] in 0..1 coordinates.
%
% Positions live in Graph so a layout survives save/load. set.Graph recognizes
% a position-only change and skips the parameter rebuild, so the editor can
% call this on drag release without tearing down every dynamic property.

i   = obj.node_index_(label);
pos = reshape(double(pos), 1, 2);
if ~all(isfinite(pos))
    error('stimgen:Patch:InvalidPosition', 'Node position must be two finite numbers.');
end

g = obj.Graph;
g.Nodes(i).Position = pos;
obj.Graph = g;
end
