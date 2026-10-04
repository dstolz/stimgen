function save_settings_prefs_(obj)
% Snapshot every remembered setting: the controls-column values
% and the View menu's display state. Read from the controls
% rather than the engine -- the controls hold what the user
% last set, applied to an engine or not. The settings windows'
% fields are the exception: each pushes every change to the
% engine immediately and may be closed by now, so the engine is
% where what the user last set lives -- and is why the
% temperature is written in Celsius and the ramp in seconds, the
% units they are read back in. Never throws: this runs on the
% window's close path.
try
    obj.set_pref_('ReferenceLevel',     sprintf('%.15g', obj.RefLevelField.Value));
    obj.set_pref_('ReferenceFrequency', sprintf('%.15g', obj.RefFreqField.Value));
    obj.set_pref_('MicSensitivity',     sprintf('%.15g', obj.MicSensField.Value));
    obj.set_pref_('AmbientTemperature', sprintf('%.15g', obj.Engine.AmbientTemperature));
    obj.set_pref_('NormativeValue',     sprintf('%.15g', obj.NormativeField.Value));
    obj.set_pref_('ExcitationVoltage',  sprintf('%.15g', obj.Engine.ExcitationVoltage));
    obj.set_pref_('ToneRampDuration',   sprintf('%.15g', obj.Engine.ToneRampDuration));
    obj.set_pref_('MaxOutputVoltage',   sprintf('%.15g', obj.Engine.MaxOutputVoltage));
    obj.set_pref_('AdcGain',            sprintf('%.15g', obj.Engine.AdcGain));
    obj.set_pref_('DacAttenuation',     sprintf('%.15g', obj.Engine.DacAttenuation));
    obj.set_pref_('AcCoupleResponse',   sprintf('%d', obj.Engine.AcCoupleResponse));
    obj.set_pref_('SpectralWindow',     char(obj.Engine.SpectralWindow));
    obj.set_pref_('SpectralFftLength',  sprintf('%d', obj.Engine.SpectralFftLength));
    obj.set_pref_('ShowLivePlots',      sprintf('%d', obj.ShowLivePlotsCheck.Value));
    obj.set_pref_('iterativeCalibration', sprintf('%d', obj.IterativeCheck.Value));
    obj.set_pref_('delayMaxDelayMs', sprintf('%.15g', obj.DelayMaxMs_));
    obj.set_pref_('delayNumClicks',  sprintf('%d', obj.DelayNumClicks_));
    if obj.ToneSweptSineCheck.Value
        obj.set_pref_('ToneLutSource', 'swept_sine');
    else
        obj.set_pref_('ToneLutSource', 'tone');
    end

    obj.set_pref_('transferLogX',    sprintf('%d', obj.Monitor.LogX));
    obj.set_pref_('spectrumGhost',   sprintf('%d', obj.Monitor.ShowGhost));
    obj.set_pref_('transferVoltage', sprintf('%d', obj.Monitor.ShowVoltage));
    obj.set_pref_('decimateWaveforms', sprintf('%d', obj.Monitor.DecimateWaveforms));
    obj.set_pref_('spectrumUnits', char(obj.Monitor.SpectrumUnits));
    obj.set_pref_('transferTab',   char(obj.TransferView_));
    types = stimgen.calibration.LiveMonitor.WeightingTypes;
    sel = types(arrayfun(@(h) strcmp(h.Checked, 'on'), obj.WeightingMenus));
    if isempty(sel)
        obj.set_pref_('weightingOverlays', '');
    else
        obj.set_pref_('weightingOverlays', char(strjoin(sel, ',')));
    end
catch ME
    stimgen.util.vprintf(-1, ME);
end
end
