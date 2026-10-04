function run_measure_reference_(obj)
obj.Engine.calibrate_reference();
obj.sync_controls_();
obj.Monitor.show_engine_state(obj.Engine);
obj.set_status_('Reference measurement complete. Remove the calibrator.', false);
end
