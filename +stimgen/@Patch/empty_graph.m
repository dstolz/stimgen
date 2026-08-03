function g = empty_graph()
% g = stimgen.Patch.empty_graph()
% An empty patch topology.
%
% Graph carries topology only. Parameter values live in the Patch's dynamic
% properties, so this struct stays small and cheap to serialize.
%
% Fields:
%   Version     - schema version, for future migrations
%   Nodes       - 1-by-N struct array: Label, Kind, Position ([x y] in 0..1
%                 canvas coordinates, used by the patch editor)
%   Connections - 1-by-M struct array: From, To, Param, Mode, Depth,
%                 PowerCompensate

g = struct( ...
    'Version',     1, ...
    'Nodes',       struct('Label', {}, 'Kind', {}, 'Position', {}), ...
    'Connections', struct('From', {}, 'To', {}, 'Param', {}, ...
                          'Mode', {}, 'Depth', {}, 'PowerCompensate', {}));
end
