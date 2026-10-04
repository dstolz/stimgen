function [tab, tg] = add_stacked_tab_(obj, titleText, tooltipKey, rowHeights, colWidths)
% One tab carrying a grid of axes, returning the grid for the
% caller to place them in. An axes needs that container: dropped
% straight into a uitab it takes its default Position rather than
% filling the tab. Heights are proportions rather than pixels --
% the tab strip resizes with the window, and a fixed height would
% leave a detail panel unreadable on a small screen and stranded
% on a large one.
arguments
    obj
    titleText (1,:) char
    tooltipKey (1,:) char
    rowHeights (1,:) cell
    colWidths (1,:) cell = {'1x'}
end
tab = uitab(obj.PlotTabs, Title=titleText, ...
    Tooltip=stimgen.util.tooltip('CalibrationGui', tooltipKey));
tg = uigridlayout(tab, [numel(rowHeights) numel(colWidths)]);
tg.RowHeight = rowHeights;
tg.ColumnWidth = colWidths;
tg.Padding = [2 2 2 2];
tg.RowSpacing = 4;
tg.ColumnSpacing = 4;
end
