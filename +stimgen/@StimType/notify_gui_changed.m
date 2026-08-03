function notify_gui_changed(obj, propName, value)
% notify_gui_changed(obj, propName, value)
% Public entry point to the protected on_gui_changed hook, for host GUIs
% that apply property edits themselves rather than through interpret_gui
% (stimgen.StimPlayer does). Call it after the property has been assigned.
%
% Parameters:
%   propName - Name of the property that the user just edited.
%   value    - Value the widget reported (display units).

arguments
    obj (1,1) stimgen.StimType
    propName (1,1) string
    value = []
end

obj.on_gui_changed(char(propName), value);
