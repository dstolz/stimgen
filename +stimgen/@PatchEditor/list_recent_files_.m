function paths = list_recent_files_(n)
% paths = stimgen.PatchEditor.list_recent_files_()
% paths = stimgen.PatchEditor.list_recent_files_(n)
% The n (default 9) recorded patch files that still exist, most recently
% MODIFIED first -- by file timestamp, not by when this editor last opened
% them, so a file re-saved from outside this session still sorts correctly.

if nargin < 1, n = 9; end

GROUP = 'stimgen_PatchEditor';
PREF  = 'RecentFiles';

if ~ispref(GROUP, PREF)
    paths = string.empty(1,0);
    return
end

paths = string(getpref(GROUP, PREF));
paths = paths(arrayfun(@(p) isfile(p), paths));
if isempty(paths)
    return
end

mtimes = arrayfun(@(p) local_mtime(p), paths);
[~, order] = sort(mtimes, 'descend');
paths = paths(order);
paths = paths(1:min(n, numel(paths)));
end


function t = local_mtime(p)
d = dir(char(p));
t = d(1).datenum;
end
