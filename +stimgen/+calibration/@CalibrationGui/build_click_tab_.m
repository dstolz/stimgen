function build_click_tab_(obj)
% The same two plots against duration instead of frequency. The
% pairing is what a click series is judged on: peak level rises
% with duration while SNR falls as it shortens, and where those
% meet is where the short end of the table stops meaning
% anything.
[obj.ClickTab, tg] = obj.add_stacked_tab_('Clicks', 'TabClicks', ...
    {'1.5x', '1x'});
obj.AxClick       = obj.tab_axes_(tg, 1, 1);
obj.AxClickDetail = obj.tab_axes_(tg, 2, 1);
end
