function ffn = save_screenshot(obj, ffn)
% save_screenshot(obj)
% save_screenshot(obj, ffn)
% ffn = save_screenshot(obj, ...)
% Write the whole window, plots and result table alike, to an image file.
%
% A spot check is evidence, and the state worth keeping is often the window
% rather than the numbers: the two waveforms overlaid, the two spectra, and
% the table beside them say together what no one column of the result file
% says on its own. The same reasoning, and the same mechanism, as
% stimgen.calibration.CalibrationGui's Save Screenshot.
%
% exportapp rather than print or getframe, because a uifigure's contents are
% not captured by either -- print sees an empty canvas and getframe depends on
% the window being unobscured on screen.
%
% Parameters:
%   ffn - full file path (optional); prompts with a dialog when omitted.
%         The extension chooses the format (.png, .jpg, .pdf, .eps).
%
% Returns:
%   ffn - the resolved path, or '' when the dialog was cancelled

arguments
    obj (1,1) stimgen.SpotCheck
    ffn (1,:) char = ''
end

if ~obj.is_open()
    error('stimgen:SpotCheck:noWindow', ...
        'There is no window to capture; this spot check was built with Show=false.');
end

if isempty(ffn)
    startDir = obj.DataPath_;
    if strlength(startDir) == 0 || ~isfolder(startDir)
        startDir = pwd;
    end
    label = regexprep(char(obj.StimulusLabel), '[^\w-]+', '_');
    if isempty(label), label = 'spotcheck'; end
    [fn, pn] = uiputfile( ...
        {'*.png', 'PNG Image (*.png)'; ...
         '*.jpg', 'JPEG Image (*.jpg)'; ...
         '*.pdf', 'PDF (*.pdf)'}, ...
        'Save Screenshot', fullfile(char(startDir), ['spotcheck_' label '.png']));
    if isequal(fn, 0)
        ffn = '';
        return
    end
    ffn = fullfile(pn, fn);
end

% The window has to have finished laying out and drawing before it is
% captured, or the image catches half-built axes.
drawnow;

try
    exportapp(obj.Figure_(), ffn);
catch ME
    error('stimgen:SpotCheck:screenshotFailed', ...
        'Could not write "%s": %s', ffn, ME.message);
end

stimgen.util.vprintf(1, 'SpotCheck: screenshot saved to "%s"', ffn);
obj.set_status_("Screenshot saved: " + string(ffn));
end
