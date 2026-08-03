function g = node_geometry_for_(patchObj, dragIdx, dragPos)
% g = stimgen.PatchEditor.node_geometry_for_(patchObj)
% g = stimgen.PatchEditor.node_geometry_for_(patchObj, dragIdx, dragPos)
% Box and port positions for every node, in canvas (0..1) coordinates.
%
% Position in the graph is the node box's top-left corner. Everything the
% editor draws and hit-tests comes from this one function, so the picture and
% the mouse always agree.
%
% Pure and static: it takes a patch and returns geometry, holding no editor
% state, which is what lets the layout be tested without opening a window.
%
% Parameters:
%   patchObj - the stimgen.Patch to lay out
%   dragIdx  - index of a node being dragged (0 for none)
%   dragPos  - live top-left corner of that node while it is being dragged
%
% Returns a struct array with fields:
%   Label, Kind, X, Y      - top-left corner
%   W, H                   - box size
%   InNames                - modulatable parameter names, top to bottom
%   InXY                   - one [x y] per input port
%   OutXY                  - [x y] of the output port

if nargin < 2, dragIdx = 0; end
if nargin < 3, dragPos = [0 0]; end

nodes = patchObj.Graph.Nodes;
g = struct('Label', {}, 'Kind', {}, 'X', {}, 'Y', {}, 'W', {}, 'H', {}, ...
           'InNames', {}, 'InXY', {}, 'OutXY', {});

for i = 1:numel(nodes)
    comp    = patchObj.component(nodes(i).Label);
    inNames = comp.modulatable_params();
    nPorts  = max(1, numel(inNames));

    pos = nodes(i).Position;
    if dragIdx == i
        pos = dragPos;   % draw at the live pointer, not the committed position
    end

    w = stimgen.PatchEditor.NODE_W;
    h = stimgen.PatchEditor.HEAD_H + nPorts * stimgen.PatchEditor.PORT_H;

    inXY = zeros(numel(inNames), 2);
    for k = 1:numel(inNames)
        inXY(k,:) = [pos(1), ...
                     pos(2) - stimgen.PatchEditor.HEAD_H - (k-0.5)*stimgen.PatchEditor.PORT_H];
    end

    g(i).Label   = nodes(i).Label;
    g(i).Kind    = nodes(i).Kind;
    g(i).X       = pos(1);
    g(i).Y       = pos(2);
    g(i).W       = w;
    g(i).H       = h;
    g(i).InNames = inNames;
    g(i).InXY    = inXY;
    g(i).OutXY   = [pos(1) + w, pos(2) - h/2];
end
end
