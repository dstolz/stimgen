function s = capture_(obj)
% s = capture_(obj)
% Snapshot the graph and every parameter value, for Revert.
%
% Edits apply to the patch immediately -- the preview would be useless
% otherwise -- so the undo story is a single restore point taken when the
% window opens.

s = struct();
s.Graph      = obj.Patch.Graph;
s.OutputNode = obj.Patch.OutputNode;
s.Names      = string.empty(1,0);
s.Values     = {};

for name = obj.Patch.UserProperties
    if name == "Graph" || name == "OutputNode" || ~isprop(obj.Patch, char(name))
        continue
    end
    s.Names(end+1)  = name; %#ok<AGROW>
    s.Values{end+1} = obj.Patch.(char(name)); %#ok<AGROW>
end
end
