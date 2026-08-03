function restore_(obj, s)
% restore_(obj, s)
% Apply a snapshot taken by capture_.
%
% Graph goes first, for the same reason it is first in UserProperties: it
% recreates the nodes, and therefore the dynamic properties, that the values
% are about to be written to.

obj.Patch.Graph      = s.Graph;
obj.Patch.OutputNode = s.OutputNode;

for k = 1:numel(s.Names)
    name = char(s.Names(k));
    if isprop(obj.Patch, name)
        obj.Patch.(name) = s.Values{k};
    end
end
end
