function remove_recent_calibration_(obj, filePath)
stimgen.util.recent_paths('StimCalibrationGui', 'RecentCalibrations', "remove", filePath);
obj.refresh_recent_calibrations_menu_();
end
