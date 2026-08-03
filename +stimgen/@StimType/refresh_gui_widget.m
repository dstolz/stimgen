function refresh_gui_widget(obj, propName)
% refresh_gui_widget(obj, propName)
% Re-apply the current propMeta entry for propName to its live GUI widget:
% label caption, numeric format/limits, and displayed value (in display
% units).
%
% Call this from on_gui_changed when one property redefines another's
% metadata, e.g. stimgen.Tone.WindowMethod switching WindowDuration between
% milliseconds, percent and carrier periods.
%
% Works for any GUI that registered its widgets with set_gui_handles, so a
% subclass needs one implementation for both the standalone create_gui panel
% and the StimPlayer parameter panel. No-op when the property has no live
% widget, so it is safe to call from headless code.
%
% Parameters:
%   propName - Property name (char or string).

propName = char(propName);

h = obj.GUIHandles;
if ~isstruct(h) || ~isfield(h, propName) || isempty(h.(propName)) || ~isvalid(h.(propName))
    return
end

meta = obj.propMeta();
if ~isfield(meta, propName)
    return
end
pm = meta.(propName);

x  = h.(propName);
ud = x.UserData;
if ~isstruct(ud)
    ud = struct();
end

% Label. Each GUI builder stores its own caption template ('%s' for
% create_gui, '%s:' for the StimPlayer panel) alongside the handle.
if isfield(ud, 'labelHandle') && ~isempty(ud.labelHandle) && isvalid(ud.labelHandle)
    labelFormat = '%s';
    if isfield(ud, 'labelFormat')
        labelFormat = ud.labelFormat;
    end
    ud.labelHandle.Text = sprintf(labelFormat, pm.label);
end

if ~isprop(x, 'Value')
    return % action widget (button): nothing to show
end

scaleValue = stimgen.StimType.display_scale(pm);
value = obj.(propName);

% Vectorizable properties render as expression text fields, which ignore
% format and limits entirely.
isNumExpr = isfield(ud, 'isNumericExpression') && ud.isNumericExpression;
if isNumExpr
    ud.propMeta = pm;
    x.UserData  = ud;
    x.Value = stimgen.StimType.localFormatPropertyValue_(value * scaleValue);
    return
end
x.UserData = ud;

if ~isnumeric(value)
    return
end

if isprop(x, 'ValueDisplayFormat') && isfield(pm, 'format')
    x.ValueDisplayFormat = pm.format;
end

if isprop(x, 'Limits')
    % Widen first: the new value and the new limits can each fall outside
    % the ones still on the widget, and either order would otherwise error.
    x.Limits = [-inf inf];
    x.Value  = value * scaleValue;
    if isfield(pm, 'limits')
        x.Limits = pm.limits;
    end
else
    x.Value = value * scaleValue;
end
