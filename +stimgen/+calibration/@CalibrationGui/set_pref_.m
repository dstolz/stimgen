function set_pref_(~, prefName, value)
groupName = 'StimCalibrationGui';
setpref(groupName, prefName, char(string(value)));
end
