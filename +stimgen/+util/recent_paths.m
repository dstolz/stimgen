function paths = recent_paths(group, list, action, varargin)
% paths = stimgen.util.recent_paths(group, list)
% paths = stimgen.util.recent_paths(group, list, "add", filePath)
% paths = stimgen.util.recent_paths(group, list, "remove", filePath)
% paths = stimgen.util.recent_paths(group, list, "menu", menu, openFcn)
% A most-recent-first list of file paths kept in MATLAB preferences, and the
% Recent submenu that offers it.
%
% StimPlayer (Recent Protocols / Banks / Calibrations) and CalibrationGui
% (Recent Protocols / Calibrations) each carried their own verbatim copy of
% this; both now call it, under their own preference group, so the lists a
% user already has are read where they were written.
%
% The list is a cell row of char paths in getpref(group, list): at most
% MaxEntries, newest first, compared case-insensitively (Windows paths), with
% empty entries dropped. It is a cell array, so it is kept out of helpers that
% coerce every stored value to char.
%
% Actions:
%   (none)   - read the list
%   "add"    - move filePath to the head (adding it if new) and store
%   "remove" - drop filePath (a remembered file that has gone) and store
%   "menu"   - rebuild menu's children from the list: "(None)" when empty,
%              else one item per path, "<n>. <name><ext> | <path>", whose
%              callback is openFcn(path)
%
% Parameters:
%   group    - preference group, e.g. 'StimPlayer'
%   list     - preference name within it, e.g. 'RecentBanks'
%   filePath - path to add or remove (char or string; trimmed)
%   menu     - uimenu to fill; an empty or deleted handle is a no-op
%   openFcn  - function handle taking the chosen path
%
% Returns:
%   paths - the list after the action (1-by-n cell of char)
if nargin < 3
    action = "get";
end
group  = char(group);
list   = char(list);
action = string(action);
if ~any(action == ["get", "add", "remove", "menu"])
    error('stimgen:util:recent_paths:badAction', ...
        'Action must be "add", "remove" or "menu" (or omitted to read), not "%s".', action);
end

MaxEntries = 9;

paths = read_(group, list);

switch action
    case "add"
        filePath = strtrim(char(varargin{1}));
        if isempty(filePath)
            return
        end
        paths(strcmpi(paths, filePath)) = [];
        paths = [{filePath}, paths];
        paths = paths(1:min(MaxEntries, numel(paths)));
        setpref(group, list, paths);

    case "remove"
        paths(strcmpi(paths, strtrim(char(varargin{1})))) = [];
        setpref(group, list, paths);

    case "menu"
        menu = varargin{1};
        openFcn = varargin{2};
        if isempty(menu) || ~isvalid(menu)
            return
        end
        delete(allchild(menu));
        if isempty(paths)
            uimenu(menu, 'Text', '(None)', 'Enable', 'off');
            return
        end
        for idx = 1:numel(paths)
            filePath = paths{idx};
            [~, fn, ext] = fileparts(filePath);
            uimenu(menu, ...
                'Text', sprintf('%d. %s%s | %s', idx, fn, ext, filePath), ...
                'MenuSelectedFcn', @(~,~) openFcn(filePath));
        end
end
end


function paths = read_(group, list)
if ispref(group, list)
    paths = getpref(group, list);
else
    paths = {};
end
if ischar(paths) || isstring(paths)
    paths = cellstr(paths);
end
paths = paths(:).';
paths = paths(~cellfun(@isempty, paths));
end
