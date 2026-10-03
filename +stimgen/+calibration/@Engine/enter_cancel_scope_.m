function scope = enter_cancel_scope_(obj)
% scope = enter_cancel_scope_(obj)
% Start one cancellable operation made of several runs. Clears any stale
% request (only at the outermost level), then makes reset_cancel_ a no-op
% until the returned onCleanup is destroyed -- by clearing it, or by the
% caller returning or erroring.
obj.reset_cancel_();
obj.CancelScopeDepth_ = obj.CancelScopeDepth_ + 1;
scope = onCleanup(@() obj.leave_cancel_scope_());
end
