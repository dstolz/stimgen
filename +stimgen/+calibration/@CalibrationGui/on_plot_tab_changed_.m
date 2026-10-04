function on_plot_tab_changed_(obj, evt)
% The tab strip is the view selector; TransferView_ only follows
% it, so what is on screen and what the object thinks is on screen
% cannot disagree. Nothing is redrawn: every panel is drawn as its
% measurement arrives and stays drawn, which is the whole point of
% the tabs.
switch evt.NewValue
    case obj.ClickTab,      obj.TransferView_ = "click";
    case obj.SweptTab,      obj.TransferView_ = "swept_sine";
    case obj.FilterTestTab, obj.TransferView_ = "filter_test";
    case obj.BackgroundTab, obj.TransferView_ = "background";
    case obj.LatencyTab,    obj.TransferView_ = "latency";
    otherwise,              obj.TransferView_ = "tone";
end
end
