function remove_recent_protocol_(obj, filePath)
stimgen.util.recent_paths('StimCalibrationGui', 'RecentProtocols', "remove", filePath);
obj.refresh_recent_protocols_menu_();
end
