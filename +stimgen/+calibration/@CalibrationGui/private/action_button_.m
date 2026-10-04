function btn = action_button_(g, row, columns, labelText, tooltipKey, callback)
% btn = action_button_(g, row, columns, labelText, tooltipKey, callback)
% Action button spanning the given column(s). Every button in this window has
% an entry in the CalibrationGui tooltip section, so the key is looked up here
% rather than passed as text.
btn = uibutton(g, Text=labelText, ButtonPushedFcn=callback);
btn.Layout.Row = row;
btn.Layout.Column = columns;
btn.Tooltip = stimgen.util.tooltip('CalibrationGui', tooltipKey);
end
