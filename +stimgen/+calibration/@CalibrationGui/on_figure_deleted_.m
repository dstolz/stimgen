function on_figure_deleted_(obj)
% The figure went without on_close_ -- close all force, or a
% delete from the command line. Nothing can be deferred any more,
% but the engine can still be told to stop.
if isvalid(obj) && obj.Busy_ && ~isempty(obj.Engine) && isvalid(obj.Engine)
    obj.Engine.cancel();
end
end
