function order = topo_order_for_(g)
% order = stimgen.Patch.topo_order_for_(g)
% Node evaluation order for a topology struct: a source renders before
% anything it modulates.
%
% Kahn's algorithm over the connection edges. Nodes with no inbound edges are
% released in graph order, so a simple patch evaluates in the order the user
% built it.
%
% This is static and takes a raw graph so that validate_graph_ can reject a
% cycle at ASSIGNMENT time. Detecting it later, during render, is not enough:
% render is reached through the Graph PostSet listener, and MATLAB downgrades
% an error thrown inside a listener callback to a warning -- the caller would
% see success and the patch would be left holding an unrenderable graph.
%
% Errors:
%   stimgen:Patch:CycleDetected - the graph contains a feedback loop. Every
%       node produces its whole buffer at once, so a cycle has no meaning.

n     = numel(g.Nodes);
order = zeros(1, n);
if n == 0
    return
end

labels = string({g.Nodes.Label});
inDeg  = zeros(1, n);
adj    = cell(1, n);

for k = 1:numel(g.Connections)
    s = find(labels == g.Connections(k).From, 1);
    t = find(labels == g.Connections(k).To,   1);
    if isempty(s) || isempty(t)
        continue
    end
    if s == t
        error('stimgen:Patch:CycleDetected', ...
            'Node "%s" is connected to its own parameter "%s".', ...
            labels(s), g.Connections(k).Param);
    end
    adj{s}(end+1) = t;
    inDeg(t)      = inDeg(t) + 1;
end

ready = find(inDeg == 0);   % ascending, i.e. graph order
done  = 0;
while ~isempty(ready)
    i        = ready(1);
    ready(1) = [];
    done     = done + 1;
    order(done) = i;
    for t = adj{i}
        inDeg(t) = inDeg(t) - 1;
        if inDeg(t) == 0
            ready = sort([ready t]);
        end
    end
end

if done < n
    stuck = labels(inDeg > 0);
    error('stimgen:Patch:CycleDetected', ...
        ['The patch contains a feedback loop through: %s. Each node renders its ' ...
         'whole buffer at once, so a cycle has no defined meaning. Remove one of ' ...
         'the connections between those nodes.'], strjoin(stuck, ' -> '));
end
end
