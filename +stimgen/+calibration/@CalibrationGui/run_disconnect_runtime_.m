function run_disconnect_runtime_(obj)
if ~isempty(obj.Host) && obj.Host.connectionState() ~= "None"
    try
        obj.Host.setMode("Idle");
    catch ME
        stimgen.util.vprintf(0, 1, 'CalibrationGui: failed to return runtime interfaces to Idle.');
        stimgen.util.vprintf(0, 1, ME);
    end
    obj.Host.release();
end

obj.Engine.set_adapter([]);
obj.update_runtime_state_();
obj.set_status_('Calibration runtime disconnected.', false);
end
