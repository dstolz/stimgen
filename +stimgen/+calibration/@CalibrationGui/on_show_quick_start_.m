function on_show_quick_start_(obj)
% Open the calibration walkthrough in a browser. The workflow is
% maintained once, on the wiki, rather than in a dialog that drifts
% out of step with the GUI it describes.
obj.open_wiki_page_(stimgen.calibration.CalibrationGui.QuickStartURL, ...
    'Calibration Quick Start', 'The calibration walkthrough');
end
