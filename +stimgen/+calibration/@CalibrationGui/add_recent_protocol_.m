function add_recent_protocol_(obj, filePath)
stimgen.util.recent_paths('StimCalibrationGui', 'RecentProtocols', "add", filePath);
obj.refresh_recent_protocols_menu_();
end
