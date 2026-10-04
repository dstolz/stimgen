function restore_display_settings_(obj)
stored = obj.get_pref_('transferLogX', '');
if any(strcmp(stored, {'0', '1'}))
    obj.Monitor.LogX = strcmp(stored, '1');
end

stored = obj.get_pref_('spectrumGhost', '');
if any(strcmp(stored, {'0', '1'}))
    obj.Monitor.ShowGhost = strcmp(stored, '1');
end

stored = obj.get_pref_('transferVoltage', '');
if any(strcmp(stored, {'0', '1'}))
    obj.Monitor.ShowVoltage = strcmp(stored, '1');
end

stored = obj.get_pref_('decimateWaveforms', '');
if any(strcmp(stored, {'0', '1'}))
    obj.Monitor.DecimateWaveforms = strcmp(stored, '1');
end

units = string(obj.get_pref_('spectrumUnits', ''));
if ismember(units, stimgen.calibration.LiveMonitor.SpectrumUnitList)
    obj.Monitor.SpectrumUnits = units;
    obj.sync_spectrum_units_menu_();
end

types = stimgen.calibration.LiveMonitor.WeightingTypes;
sel = split(string(obj.get_pref_('weightingOverlays', '')), ',');
checked = ismember(types, sel);
if any(checked)
    for k = 1:numel(types)
        obj.WeightingMenus(k).Checked = ...
            matlab.lang.OnOffSwitchState(checked(k));
    end
    obj.Monitor.Weightings = types(checked);
end

% The tab last read, so a window reopens where its operator left
% off. Only the selection is remembered -- what the panels held
% belonged to a session that has ended.
%
% "calibration" is what a window wrote before the lookup tables
% were split into a tab per stimulus; it means the tone tab now,
% which is where a rig's calibration starts. Translated rather
% than discarded so the first launch after an update opens where
% the last one was left, and rewritten on the way out.
tab = string(obj.get_pref_('transferTab', ''));
if tab == "calibration"
    tab = "tone";
end
if ismember(tab, ["tone", "click", "swept_sine", "filter_test", ...
        "background", "latency"])
    obj.set_transfer_view_(tab);
end

% Everything above writes the monitor; this is what makes the
% controls that mirror it agree with what was restored.
obj.sync_display_controls_();
end
