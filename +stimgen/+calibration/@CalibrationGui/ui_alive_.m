function tf = ui_alive_(obj)
% True while the window this object draws into still exists.
tf = isvalid(obj) && ~isempty(obj.Figure) && isvalid(obj.Figure);
end
