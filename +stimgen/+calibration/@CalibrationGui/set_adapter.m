function set_adapter(obj, adapter)
% set_adapter(obj, adapter)
% Attach/replace the hardware adapter used for live calibration.
arguments
    obj
    adapter (1,1) stimgen.calibration.HwAdapter
end
obj.Engine.set_adapter(adapter);
obj.update_runtime_state_();
obj.set_status_('Adapter attached. Ready for live calibration.', false);
end
