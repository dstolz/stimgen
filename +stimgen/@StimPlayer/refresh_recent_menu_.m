function refresh_recent_menu_(obj, handleField, prefName, openFcn)
% refresh_recent_menu_() - Rebuild one Recent submenu, most recent first.
if ~isfield(obj.handles, handleField)
    return
end
stimgen.util.recent_paths('StimPlayer', prefName, "menu", ...
    obj.handles.(handleField), openFcn);
end
