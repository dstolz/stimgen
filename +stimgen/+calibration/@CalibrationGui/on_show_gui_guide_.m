function on_show_gui_guide_(obj)
% Open this window's own section of the walkthrough -- the tour
% that names every control in the order a session uses them.
obj.open_wiki_page_(stimgen.calibration.CalibrationGui.GuiGuideURL, ...
    'Calibration GUI Guide', 'The guide to this window');
end
