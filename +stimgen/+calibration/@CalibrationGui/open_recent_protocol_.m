function open_recent_protocol_(obj, filePath)
% Re-run Initialize Runtime From Protocol with a remembered path.
obj.with_busy_state_(@() obj.run_initialize_runtime_(filePath), 'Initializing calibration runtime...');
end
