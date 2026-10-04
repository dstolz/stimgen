function refresh_recent_menu_(~, menu, prefName, openFcn)
% Rebuild a Recent-files submenu (most recent first) from stored preferences.
stimgen.util.recent_paths('StimCalibrationGui', prefName, "menu", menu, openFcn);
end
