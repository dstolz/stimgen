function set_status_(obj, msg, isError)
% Guarded: a run that outlives its window (see with_busy_state_)
% may still report on its way out.
if isempty(obj.StatusLabel) || ~isvalid(obj.StatusLabel)
    return
end
if isError
    obj.StatusLabel.FontColor = [0.7 0 0];
else
    obj.StatusLabel.FontColor = [0 0 0];
end
obj.StatusLabel.Text = msg;
% A result line -- a test verdict, a background summary -- is
% routinely wider than the controls column, and the label clips it.
% The tooltip is where the rest of it stays reachable.
obj.StatusLabel.Tooltip = msg;
end
