function order = topo_order_(obj)
% order = topo_order_(obj)
% Node evaluation order for this patch's graph.
%
% The graph was already checked for cycles when Graph was assigned, so this is
% the fast path; the shared implementation still raises if something slipped
% through.

order = stimgen.Patch.topo_order_for_(obj.Graph);
end
