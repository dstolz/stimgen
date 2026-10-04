function sync_spectrum_units_menu_(obj)
% Check the item matching the monitor's unit, so the menu follows
% the monitor even when something other than the menu set it.
if isempty(obj.SpectrumUnitMenus)
    return
end
for h = obj.SpectrumUnitMenus
    h.Checked = matlab.lang.OnOffSwitchState(h.UserData == obj.Monitor.SpectrumUnits);
end
end
