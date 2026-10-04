function ax = tab_axes_(~, tg, row, col)
% One axes in a tab's grid.
ax = uiaxes(tg);
ax.Layout.Row = row;
ax.Layout.Column = col;
grid(ax, 'on');
end
