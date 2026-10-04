function dd = dropdown_row_(g, row, labelText, itemLabels, itemValues, tip)
% dd = dropdown_row_(g, row, labelText, itemLabels, itemValues)
% dd = dropdown_row_(g, row, labelText, itemLabels, itemValues, tip)
% Right-aligned caption and a dropdown whose ItemsData carries the value a
% caller acts on, so the list can read in prose while Value stays the name or
% number the engine takes.
arguments
    g
    row (1,1) double
    labelText (1,:) char
    itemLabels (1,:) string
    itemValues
    tip (1,:) char = ''
end
lbl = uilabel(g, Text=labelText, HorizontalAlignment='right');
lbl.Layout.Row = row;
lbl.Layout.Column = 1;

dd = uidropdown(g, Items=cellstr(itemLabels), ItemsData=itemValues);
dd.Layout.Row = row;
dd.Layout.Column = 2;

if ~isempty(tip)
    lbl.Tooltip = tip;
    dd.Tooltip = tip;
end
end
