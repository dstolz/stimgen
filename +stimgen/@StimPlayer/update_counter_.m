function update_counter_(obj)
% update_counter_() - Refresh the stimulus counter label in the GUI.
h = obj.handles;
if ~isfield(h,'Counter') || ~isvalid(h.Counter)
    return
end
h.Counter.Text = sprintf('%d / %d', obj.presented_count_(), obj.total_count_());
end
