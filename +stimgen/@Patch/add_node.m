function add_node(obj, label, kind, varargin)
% add_node(obj, label, kind)
% add_node(obj, label, kind, ParamName, Value, ...)
% Add a component node to the patch.
%
% Parameters:
%   label - unique node label; must be a valid MATLAB identifier, because it
%           becomes part of each of the node's parameter property names
%   kind  - a component kind from stimgen.components.list()
%   Name/Value pairs set that node's parameters after it is created
%
% Example:
%   p.add_node("LFO1", "Oscillator", Frequency = 10, Shape = "sine");

label = string(label);
kind  = string(kind);

if any(obj.node_labels() == label)
    error('stimgen:Patch:DuplicateNodeLabel', ...
        'This patch already has a node labelled "%s".', label);
end

g = obj.Graph;
g.Nodes(end+1) = struct('Label', label, 'Kind', kind, 'Position', []);
obj.Graph = g;   % validates, rebuilds parameters, fires update_signal

for k = 1:2:numel(varargin)
    obj.(char(stimgen.Patch.flat_name_(label, varargin{k}))) = varargin{k+1};
end
end
