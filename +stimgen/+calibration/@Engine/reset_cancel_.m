function reset_cancel_(obj)
% Clear any pending cancellation request. Called at the start of every
% cancellable run so a stale request from a prior run can't abort a new one.
%
% Inside a cancel scope (run_cancellable, refine_lut_) several runs make up
% one operation, and only the scope's entry clears the request: otherwise a
% Stop pressed between two of those runs -- after the sweep's last check,
% before the refinement's first test -- would be wiped by the next run.
if obj.CancelScopeDepth_ > 0
    return
end
obj.CancelRequested_ = false;
end
