function on_load_(obj)
if ~obj.confirm_discard_('loading another calibration')
    obj.set_status_('Load cancelled.', false);
    return
end
obj.with_busy_state_(@() obj.run_load_(''), 'Loading calibration file...');
end
