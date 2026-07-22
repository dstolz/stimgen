function interpret_gui(obj, src, event)
% interpret_gui(obj, src, event)
% Parse and apply a widget value-change event to the corresponding property.
% Numeric expression fields are evaluated via evaluate_property_expression_.
% Widget values are in display units (e.g. milliseconds for time properties)
% and are divided by the propMeta display scale before assignment.
% Invalid values are rejected and the widget is reverted to the prior value.

isNumExpr = isstruct(src.UserData) && isfield(src.UserData, 'isNumericExpression') && src.UserData.isNumericExpression;
scaleValue = stimgen.StimType.display_scale(obj.propMeta(), src.Tag);
try
    if isNumExpr
        % The expression context is also in display units, so the result
        % needs only a single conversion back to property units.
        value = obj.evaluate_property_expression_(src.Tag, char(string(event.Value))) / scaleValue;
    elseif isnumeric(event.Value)
        value = event.Value / scaleValue;
    else
        value = event.Value;
    end
    obj.(src.Tag) = value;
catch ME
    revert_widget_(obj, src, event, scaleValue, isNumExpr);
    fig = ancestor(src, 'matlab.ui.Figure');
    if ~isempty(fig) && isvalid(fig)
        uialert(fig, ME.message, sprintf('Invalid value for %s', src.Tag));
    end
    return
end
if isNumExpr
    src.Value = stimgen.StimType.localFormatPropertyValue_(obj.(src.Tag) * scaleValue);
end
obj.on_gui_changed(src.Tag, event.Value);
obj.call_update_signal_with_variant_cycle_();
end


function revert_widget_(obj, src, event, scaleValue, isNumExpr)
% revert_widget_(obj, src, event, scaleValue, isNumExpr)
% Restore a widget to the property's current value (in display units) after
% a rejected edit. The property itself is left untouched: the failed
% assignment never took effect.
currentValue = obj.(src.Tag);
if isNumExpr
    src.Value = stimgen.StimType.localFormatPropertyValue_(currentValue * scaleValue);
elseif isnumeric(currentValue) && isnumeric(event.Value)
    src.Value = currentValue * scaleValue;
elseif islogical(currentValue)
    src.Value = logical(currentValue);
elseif isstring(currentValue) || ischar(currentValue)
    src.Value = char(currentValue);
else
    src.Value = event.PreviousValue;
end
end
