function ok = apply_controls_to_engine_(obj)
ok = false;
try
    if obj.ToneSweptSineCheck.Value
        toneLutSource = "swept_sine";
    else
        toneLutSource = "tone";
    end
    % Max Output Voltage, AC Couple, Ambient Temperature,
    % Excitation Voltage and Tone Rise/Fall Time are absent
    % deliberately: their settings windows push them to the engine
    % the moment they change, and their controls exist only while
    % those windows are open.
    obj.Engine.set_configuration( ...
        ReferenceLevel=obj.RefLevelField.Value, ...
        ReferenceFrequency=obj.RefFreqField.Value, ...
        MicSensitivity=obj.MicSensField.Value, ...
        NormativeValue=obj.NormativeField.Value, ...
        ShowLivePlots=obj.ShowLivePlotsCheck.Value, ...
        ToneLutSource=toneLutSource);
    ok = true;
    % Every run starts here, so saving on success means a hard
    % MATLAB exit costs at most the edits since the last run.
    obj.save_settings_prefs_();
    % The unity-gain readout is anchored to NormativeValue and
    % the LUT choice, both of which may have just changed.
    obj.refresh_level_reference_label_();
catch ME
    obj.set_status_(sprintf('Parameter update failed: %s', ME.message), true);
    uialert(obj.Figure, ME.message, 'Parameter Error', Icon='error');
end
end
