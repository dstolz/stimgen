function dialog_key_(fig, evt)
% Escape cancels. Return is left to the field being typed in, where it
% commits the value.
if strcmp(evt.Key, 'escape')
    finish_dialog_(fig, false);
end
end
