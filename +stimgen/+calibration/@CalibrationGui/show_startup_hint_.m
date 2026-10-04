function show_startup_hint_(obj)
% Provide immediate guidance on the next actionable step.
if isempty(obj.Engine.Adapter)
    obj.set_status_('No adapter attached. Initialize Runtime From Protocol, then Attach Adapter.', true);
    return
end

if obj.Engine.IsCalibrated
    obj.set_status_('Calibration loaded. Review plots or save updates.', false);
else
    obj.set_status_('Ready. Start with "Measure Reference", then "Calibrate Tones".', false);
end
end
