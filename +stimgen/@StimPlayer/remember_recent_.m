function remember_recent_(obj, prefName, action, filePath)
% remember_recent_() - Add a path to, or drop it from, a recent
% list (stimgen.util.recent_paths), then rebuild the menus.
stimgen.util.recent_paths('StimPlayer', prefName, action, filePath);
obj.refresh_recent_menus_;
end
