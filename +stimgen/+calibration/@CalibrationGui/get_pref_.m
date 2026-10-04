function value = get_pref_(~, prefName, defaultValue)
groupName = 'StimCalibrationGui';
if ispref(groupName, prefName)
    value = getpref(groupName, prefName);
else
    value = defaultValue;
end
value = char(string(value));
end
