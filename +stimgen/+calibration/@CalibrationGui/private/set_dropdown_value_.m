function set_dropdown_value_(dd, value, labelFcn)
% set_dropdown_value_(dd, value, labelFcn)
% Select value in a dropdown, appending it to the list first when it is not
% already offered. A saved file or a scripted engine may hold a setting the
% GUI's list never included; snapping to the nearest offered value would edit
% the engine behind the user's back just for opening a window.
if ~isempty(dd.ItemsData) && any(dd.ItemsData == value)
    dd.Value = value;
    return
end
dd.Items = [dd.Items, {char(labelFcn(value))}];
dd.ItemsData = [dd.ItemsData, value];
dd.Value = value;
end
