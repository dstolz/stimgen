function on_key_(obj, ~, event)
% on_key_(obj, src, event) - Delete or Backspace removes the selection.

if obj.closing
    return
end

switch event.Key
    case {'delete', 'backspace'}
        if obj.selKind ~= ""
            obj.delete_selection_();
        end
    case 'escape'
        if obj.dragMode ~= "idle"
            obj.dragMode = "idle";
            obj.dragIdx  = 0;
            obj.refresh_all_();
        end
end
end
