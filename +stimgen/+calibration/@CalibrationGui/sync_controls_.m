function sync_controls_(obj)
obj.RefLevelField.Value = obj.Engine.ReferenceLevel;
obj.RefFreqField.Value = obj.Engine.ReferenceFrequency;
obj.MicSensField.Value = obj.Engine.MicSensitivity;
obj.NormativeField.Value = obj.Engine.NormativeValue;
obj.ShowLivePlotsCheck.Value = obj.Engine.ShowLivePlots;
obj.ToneSweptSineCheck.Value = obj.Engine.ToneLutSource == "swept_sine";
% One cell entry per line: what a text area holds, and what
% splitlines makes of the single string the engine keeps.
obj.NotesArea.Value = cellstr(splitlines(obj.Engine.Notes));
obj.sync_hardware_dialog_();
obj.sync_delay_dialog_();
obj.sync_excitation_dialog_();
end
