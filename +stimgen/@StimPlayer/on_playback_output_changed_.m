function on_playback_output_changed_(obj)
% on_playback_output_changed_() - React to a committed preview-output switch.
% Syncs the dropdown (for programmatic assignment) and refreshes
% the calibration status label, whose meaning depends on the
% route. Nothing here may throw: the value is already committed.
% (The hardware rate is adopted by set.PlaybackOutput, before.)

h = obj.handles;
if isfield(h, 'OutputDD') && ~isempty(h.OutputDD) && isvalid(h.OutputDD)
    h.OutputDD.Value = obj.PlaybackOutput;
end

if obj.PlaybackOutput == "Hardware"
    obj.set_status_("Preview output: calibrated hardware.");
else
    obj.set_status_("Preview output: computer speakers.");
end

obj.update_calibration_status_;
obj.sync_control_enable_;
end
