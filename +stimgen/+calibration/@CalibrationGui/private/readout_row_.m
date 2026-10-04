function val = readout_row_(g, row, labelText, initialText, tip)
% val = readout_row_(g, row, labelText, initialText, tip)
% Right-aligned caption and a left-aligned label the GUI writes into. A label
% rather than a disabled field: nothing here is editable, and greyed-out text
% would be harder to read than the value deserves.
arguments
    g
    row (1,1) double
    labelText (1,:) char
    initialText (1,:) char
    tip (1,:) char = ''
end
lbl = uilabel(g, Text=labelText, HorizontalAlignment='right');
lbl.Layout.Row = row;
lbl.Layout.Column = 1;

val = uilabel(g, Text=initialText, HorizontalAlignment='left');
val.Layout.Row = row;
val.Layout.Column = 2;

if ~isempty(tip)
    lbl.Tooltip = tip;
    val.Tooltip = tip;
end
end
