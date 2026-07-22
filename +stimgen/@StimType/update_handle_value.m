function update_handle_value(obj, src, ~)
% update_handle_value(obj, src, event)
% Sync the GUI widget for src.Name to the current property value, converting
% into display units (e.g. milliseconds for time properties) first.

propName = char(src.Name);
h = obj.GUIHandles;
if ~isstruct(h) || ~isfield(h, propName) || ~isvalid(h.(propName))
    return
end

x = h.(propName);
scaleValue = stimgen.StimType.display_scale(obj.propMeta(), propName);
value = obj.(propName);

isNumExpr = isstruct(x.UserData) && isfield(x.UserData, 'isNumericExpression') && x.UserData.isNumericExpression;
if isNumExpr
    x.Value = stimgen.StimType.localFormatPropertyValue_(value * scaleValue);
elseif isnumeric(value) && ~isa(x, 'matlab.ui.control.EditField')
    x.Value = value * scaleValue;
elseif isstring(value) || ischar(value)
    x.Value = char(value);
else
    x.Value = value;
end
