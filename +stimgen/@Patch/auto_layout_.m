function g = auto_layout_(g)
% g = stimgen.Patch.auto_layout_(g)
% Assign node positions by graph depth: a layered left-to-right layout.
%
% Each node's column is the LONGEST path from any source to it, so a node
% always sits to the right of everything that feeds it and wires flow one way
% instead of doubling back. Nodes sharing a column are spread down the canvas.
%
% Laying out by evaluation order instead would place, say, an LFO that feeds a
% mid-chain node in the wrong column and cross its wire over the whole graph.
%
% Positions are the box's top-left corner, in canvas (0..1) coordinates, and
% stop short of the right edge to stay clear of the editor's OUT terminal.

n = numel(g.Nodes);
if n == 0
    return
end

labels = string({g.Nodes.Label});
depth  = zeros(1, n);

% Relax along a topological order: by the time a node is visited, every
% predecessor already has its final depth.
for i = stimgen.Patch.topo_order_for_(g)
    for k = 1:numel(g.Connections)
        if g.Connections(k).From ~= labels(i)
            continue
        end
        t = find(labels == g.Connections(k).To, 1);
        if ~isempty(t)
            depth(t) = max(depth(t), depth(i) + 1);
        end
    end
end

X0 = 0.05;   % left margin
X1 = 0.68;   % last column, leaving room for NODE_W plus the OUT terminal
YT = 0.92;   % top row
YB = 0.44;   % bottom row, leaving room for the tallest box

maxD = max(depth);
for d = 0:maxD
    idx = find(depth == d);
    if maxD > 0
        x = X0 + (X1 - X0) * d / maxD;
    else
        x = X0;
    end

    m = numel(idx);
    for j = 1:m
        if m == 1
            y = 0.70;                                   % centred in the column
        else
            y = YT - (YT - YB) * (j-1) / (m - 1);
        end
        g.Nodes(idx(j)).Position = [x y];
    end
end
end
