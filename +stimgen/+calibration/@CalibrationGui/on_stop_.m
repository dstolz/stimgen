function on_stop_(obj)
% Request cancellation of the running calibration. Takes effect at
% the next measurement boundary, not immediately.
% Stop stays enabled: a second press is harmless, and a request
% that had to be repeated must not find the button disabled.
obj.Engine.cancel();
obj.set_status_('Stopping...', false);
end
