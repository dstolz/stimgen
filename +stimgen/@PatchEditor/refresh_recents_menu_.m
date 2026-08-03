function refresh_recents_menu_(obj)
% refresh_recents_menu_(obj)
% Rebuild the Recents submenu from the 9 most recently modified .spatch
% files on record. Called after every successful Save/Load, and once when
% the menu is first built, so the list reflects files touched by other
% editor windows too.

if isempty(obj.fig) || ~isvalid(obj.fig) || ~isfield(obj.h, 'RecentsMenu')
    return
end

m = obj.h.RecentsMenu;
delete(m.Children);

paths = stimgen.PatchEditor.list_recent_files_(9);

if isempty(paths)
    uimenu(m, 'Text', '(No recent patches)', 'Enable', 'off');
    return
end

for k = 1:numel(paths)
    p = char(paths(k));
    [~, name, ext] = fileparts(p);
    uimenu(m, 'Text', [name ext], 'Tooltip', p, ...
        'MenuSelectedFcn', @(~,~) obj.load_patch_(p));
end
end
