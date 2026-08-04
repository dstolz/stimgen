function reset_cancel_(obj)
% Clear any pending cancellation request. Called at the start of every
% cancellable run so a stale request from a prior run can't abort a new one.
obj.CancelRequested_ = false;
end
