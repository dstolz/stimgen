function set_transfer_view_(obj, view)
% Bring one of the plot tabs to the front. Everything that
% selects a view programmatically comes through here -- a
% finished background capture, a finished delay probe, a sweep
% about to fill the transfer panel in -- so the tab on screen and
% TransferView_ cannot disagree. A user clicking a tab arrives at
% the same state through on_plot_tab_changed_ instead.
%
% Nothing is redrawn: every panel already holds its measurement.
arguments
    obj
    view (1,1) string {mustBeMember(view, ["tone", "click", ...
        "swept_sine", "filter_test", "background", "latency"])}
end
switch view
    case "click",       tab = obj.ClickTab;
    case "swept_sine",  tab = obj.SweptTab;
    case "filter_test", tab = obj.FilterTestTab;
    case "background",  tab = obj.BackgroundTab;
    case "latency",     tab = obj.LatencyTab;
    otherwise,          tab = obj.ToneTab;
end
if ~isempty(obj.PlotTabs) && isgraphics(obj.PlotTabs) && isgraphics(tab)
    obj.PlotTabs.SelectedTab = tab;
end
% Setting SelectedTab does not fire SelectionChangedFcn, so the
% state this callback would have written is written here.
obj.TransferView_ = view;
end
