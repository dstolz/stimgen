function capture_finished_(obj)
% capture_finished_() - Clear the in-progress flag after a capture.
% Called from capture_stim's onCleanup, so an error or an
% interrupted acquisition cannot leave capture disabled for good.
obj.Capturing_ = false;
obj.sync_capture_controls_;
end
