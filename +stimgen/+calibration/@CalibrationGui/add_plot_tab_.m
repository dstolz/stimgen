function [tab, ax] = add_plot_tab_(obj, titleText, tooltipKey)
% One tab in the plots panel, carrying a single axes.
[tab, tg] = obj.add_stacked_tab_(titleText, tooltipKey, {'1x'});
ax = obj.tab_axes_(tg, 1, 1);
end
