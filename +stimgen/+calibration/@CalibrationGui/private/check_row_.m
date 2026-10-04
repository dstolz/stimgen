function chk = check_row_(g, row, labelText, tip, callback)
% chk = check_row_(g, row, labelText)
% chk = check_row_(g, row, labelText, tip)
% chk = check_row_(g, row, labelText, tip, callback)
% Right-aligned caption and an unlabelled checkbox, so a toggle lines up with
% the fields above it instead of starting its own column.
arguments
    g
    row (1,1) double
    labelText (1,:) char
    tip (1,:) char = ''
    callback = []
end
lbl = uilabel(g, Text=labelText, HorizontalAlignment='right');
lbl.Layout.Row = row;
lbl.Layout.Column = 1;

chk = uicheckbox(g, Text='');
chk.Layout.Row = row;
chk.Layout.Column = 2;

if ~isempty(callback)
    chk.ValueChangedFcn = callback;
end
if ~isempty(tip)
    lbl.Tooltip = tip;
    chk.Tooltip = tip;
end
end
