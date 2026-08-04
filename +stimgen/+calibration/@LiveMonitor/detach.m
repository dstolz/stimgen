function detach(obj)
% detach(obj)
% Stop following the current engine. Graphics already drawn are left alone.

if ~isempty(obj.Listener_) && isvalid(obj.Listener_)
    delete(obj.Listener_);
end
obj.Listener_ = [];

if ~isempty(obj.Engine) && isvalid(obj.Engine)
    obj.Engine.unregister_monitor_(obj);
end
obj.Engine = [];
end
