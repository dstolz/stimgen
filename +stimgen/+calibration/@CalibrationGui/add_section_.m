function [g, h] = add_section_(~, parent, row, titleText, rowHeights)
% [g, h] = add_section_(obj, parent, row, titleText, rowHeights)
% Titled section panel in the controls column, returning its
% label/widget grid and the pixel height the column must reserve
% for it. The height is computed rather than left as '1x' because
% the column scrolls, and a scrollable grid collapses a '1x' row to
% its minimum.
p = uipanel(parent, Title=titleText);
p.Layout.Row = row;
p.Layout.Column = 1;

g = uigridlayout(p, [numel(rowHeights) 2]);
g.RowHeight = num2cell(rowHeights);
% Captions get the wider share: they carry the units, the fields
% hold three or four digits.
g.ColumnWidth = {'1.3x', '1x'};
g.Padding = [8 6 8 6];
g.RowSpacing = 4;
g.ColumnSpacing = 8;

h = sum(rowHeights) + 4*(numel(rowHeights)-1) + 12 + 26;
end
