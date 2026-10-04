% Row builders for the controls column. One call per row keeps a section's
% code the same shape as the section on screen, and puts the tooltip on the
% caption as well as the widget so the whole row is a hover target.

function fld = numeric_row_(g, row, labelText, limits, format, tip)
% fld = numeric_row_(g, row, labelText, limits, format)
% fld = numeric_row_(g, row, labelText, limits, format, tip)
% Right-aligned caption and a numeric edit field.
arguments
    g
    row (1,1) double
    labelText (1,:) char
    limits (1,2) double
    format (1,:) char
    tip (1,:) char = ''
end
lbl = uilabel(g, Text=labelText, HorizontalAlignment='right');
lbl.Layout.Row = row;
lbl.Layout.Column = 1;

fld = uieditfield(g, 'numeric');
fld.Layout.Row = row;
fld.Layout.Column = 2;
fld.Limits = limits;
fld.ValueDisplayFormat = format;

if ~isempty(tip)
    lbl.Tooltip = tip;
    fld.Tooltip = tip;
end
end
