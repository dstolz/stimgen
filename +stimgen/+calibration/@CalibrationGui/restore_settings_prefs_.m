function restore_settings_prefs_(obj)
% Reapply the settings the user last worked with, written by
% save_settings_prefs_. Engine-side settings are restored per
% field and only where the engine still holds its factory
% default, so values arriving on a supplied engine win -- and
% not at all when the engine is calibrated, since its settings
% document the measurement. Display settings belong to this
% window rather than the engine and are always restored.
if ~obj.Engine.IsCalibrated
    obj.restore_engine_settings_();
end
obj.restore_display_settings_();

% GUI-owned workflow toggle, not an engine setting: whether each
% tone/click sweep is followed by the iterative refinement.
stored = obj.get_pref_('iterativeCalibration', '');
if any(strcmp(stored, {'0', '1'}))
    obj.IterativeCheck.Value = strcmp(stored, '1');
end

% Also GUI-owned, and restored unconditionally: no engine holds
% the probe's parameters, so there is nothing they could lose to.
% The keys are the ones the old prompt wrote, so a rig that had
% raised its search bound keeps it.
v = str2double(obj.get_pref_('delayMaxDelayMs', ''));
if isfinite(v) && v > 0
    obj.DelayMaxMs_ = v;
end
v = str2double(obj.get_pref_('delayNumClicks', ''));
if isfinite(v) && v >= 1
    obj.DelayNumClicks_ = round(v);
end
end
