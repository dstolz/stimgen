function leave_cancel_scope_(obj)
% Close one enter_cancel_scope_ level. Runs from an onCleanup, so it must not
% throw; the engine may already be gone when a caller is torn down.
if isvalid(obj)
    obj.CancelScopeDepth_ = max(obj.CancelScopeDepth_ - 1, 0);
end
end
