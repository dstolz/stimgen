function lbl = heading_row_(g, row, titleText)
% lbl = heading_row_(g, row, titleText)
% Bold full-width heading that groups the rows beneath it. Used where a
% settings window carries two kinds of setting that happen to share a
% consequence but not a reason.
lbl = uilabel(g, Text=titleText, FontWeight='bold');
lbl.Layout.Row = row;
lbl.Layout.Column = [1 2];
end
