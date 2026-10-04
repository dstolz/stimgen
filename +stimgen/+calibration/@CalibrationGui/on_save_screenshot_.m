function on_save_screenshot_(obj)
% Save the entire window -- controls column, footer and plots
% alike -- to an image file. exportapp is used because it is the
% one capture that includes UI components; print and copygraphics
% render the axes alone. The folder is remembered separately from
% the .esgc folders: screenshots go to notebooks and reports, not
% to the calibration data tree.
startDir = obj.get_pref_('ScreenshotDir', '');
if isempty(startDir) || ~isfolder(startDir)
    startDir = pwd;
end
defaultName = sprintf('StimCalibration_%s.png', ...
    char(datetime('now', Format='yyyyMMdd_HHmmss')));
[fn, pn] = uiputfile( ...
    {'*.png', 'PNG image (*.png)'; ...
     '*.jpg', 'JPEG image (*.jpg)'; ...
     '*.pdf', 'PDF (*.pdf)'}, ...
    'Save Screenshot', fullfile(startDir, defaultName));
% uiputfile drops the main window behind whichever window last
% had focus; put it back where exportapp is about to capture it.
obj.show();
if isequal(fn, 0)
    obj.set_status_('Screenshot cancelled.', false);
    return
end

ffn = fullfile(pn, fn);
try
    exportapp(obj.Figure, ffn);
catch ME
    stimgen.util.vprintf(0, 1, ME);
    obj.set_status_(sprintf('Screenshot failed: %s', ME.message), true);
    return
end
obj.set_pref_('ScreenshotDir', pn);
obj.set_status_(sprintf('Screenshot saved to %s', ffn), false);
end
