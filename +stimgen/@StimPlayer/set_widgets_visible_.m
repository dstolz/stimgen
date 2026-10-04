function set_widgets_visible_(obj, fieldNames, show)
% set_widgets_visible_(fieldNames, show) - Toggle Visible on handles.
state = 'off';
if show
    state = 'on';
end
for i = 1:numel(fieldNames)
    f = fieldNames{i};
    if isfield(obj.handles, f) && ~isempty(obj.handles.(f)) && isvalid(obj.handles.(f))
        obj.handles.(f).Visible = state;
    end
end
end
