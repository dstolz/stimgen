function s = topology_signature_(g)
% s = stimgen.Patch.topology_signature_(g)
% A string capturing everything about a graph EXCEPT node positions.
%
% set.Graph uses this to tell a real topology edit from a canvas drag, so that
% moving a node does not tear down and rebuild the dynamic parameter
% properties (which would also churn UserProperties for a cosmetic change).

s = "v" + string(g.Version);

for i = 1:numel(g.Nodes)
    s = s + "|n:" + g.Nodes(i).Label + ":" + g.Nodes(i).Kind;
end

for k = 1:numel(g.Connections)
    c = g.Connections(k);
    s = s + "|c:" + c.From + ">" + c.To + "." + c.Param + ":" + c.Mode + ...
        ":" + string(c.Depth) + ":" + string(c.PowerCompensate);
end
end
