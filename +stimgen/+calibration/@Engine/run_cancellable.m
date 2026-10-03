function varargout = run_cancellable(obj, fcn)
% varargout = run_cancellable(obj, fcn)
% Run fcn() as one cancellable operation.
%
% Every cancellable engine run clears the cancel request at entry, so that a
% stale Stop cannot abort a fresh run. An operation that chains several runs
% -- a sweep followed by its refinement, which itself runs test passes --
% would therefore lose a cancel() that arrived between two of them. Inside
% fcn, only this entry clears the request, so the cancel lands at the next
% run's first check instead.
%
% Parameters:
%   fcn - function handle taking no arguments
%
% Returns:
%   whatever fcn returns
scope = obj.enter_cancel_scope_(); %#ok<NASGU>
[varargout{1:nargout}] = fcn();
end
