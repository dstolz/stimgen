function record_recent_file_(ffn)
% stimgen.PatchEditor.record_recent_file_(ffn)
% Record a patch file path as most-recently-used, for the Recents menu.
%
% Stored via MATLAB preferences (not an instance property) so the list is
% shared across editor windows and survives across MATLAB sessions.

GROUP   = 'stimgen_PatchEditor';
PREF    = 'RecentFiles';
MAXKEEP = 20;

ffn = string(ffn);

if ispref(GROUP, PREF)
    paths = string(getpref(GROUP, PREF));
else
    paths = string.empty(1,0);
end

paths = [ffn, paths(paths ~= ffn)];
if numel(paths) > MAXKEEP
    paths = paths(1:MAXKEEP);
end

setpref(GROUP, PREF, paths);
end
