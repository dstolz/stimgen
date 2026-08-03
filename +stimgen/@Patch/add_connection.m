function add_connection(obj, from, to, param, varargin)
% add_connection(obj, from, to, param)
% add_connection(obj, from, to, param, Mode = ..., Depth = ..., PowerCompensate = ...)
% Route one node's output into another node's parameter.
%
% Parameters:
%   from  - source node label
%   to    - target node label
%   param - a modulatable parameter of the target (see the component's
%           modulatable_params)
%   Mode            - see stimgen.Patch.mode_names; default "AM"
%   Depth           - modulation depth, interpreted per mode; default 1
%   PowerCompensate - equalize power across depths, AM only; default false
%
% Replacing an existing connection between the same source, target and
% parameter updates it in place rather than stacking a duplicate.
%
% Example:
%   p.add_connection("LFO1", "Osc1", "Frequency", Mode = "Add", Depth = 1000);

ip = inputParser;
ip.addParameter('Mode',            "AM");
ip.addParameter('Depth',           1);
ip.addParameter('PowerCompensate', false);
ip.parse(varargin{:});
r = ip.Results;

from  = string(from);
to    = string(to);
param = string(param);

c = struct('From', from, 'To', to, 'Param', param, ...
           'Mode', string(r.Mode), 'Depth', double(r.Depth), ...
           'PowerCompensate', logical(r.PowerCompensate));

g = obj.Graph;
hit = [];
if ~isempty(g.Connections)
    hit = find(string({g.Connections.From})  == from & ...
               string({g.Connections.To})    == to   & ...
               string({g.Connections.Param}) == param, 1);
end

if isempty(hit)
    g.Connections(end+1) = c;
else
    g.Connections(hit) = c;
end
obj.Graph = g;
end
