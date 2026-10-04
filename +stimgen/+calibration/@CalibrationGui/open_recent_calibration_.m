function open_recent_calibration_(obj, filePath)
% Re-run Load .esgc with a remembered path.
if ~obj.confirm_discard_('loading another calibration')
    obj.set_status_('Load cancelled.', false);
    return
end
obj.with_busy_state_(@() obj.run_load_(filePath), 'Loading calibration file...');
end
