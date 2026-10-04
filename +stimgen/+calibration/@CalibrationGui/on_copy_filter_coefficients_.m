function on_copy_filter_coefficients_(obj)
% Put the equalizer's taps on the system clipboard, one per line
% and nothing else, so the text pastes as-is into an RPvds
% coefficient file, a spreadsheet column, or another language's
% array literal. The design metadata a reader needs alongside them
% -- tap count and design rate -- goes to the status line instead
% of into the text, which stays purely numeric.
C = obj.Engine.CalibrationData;
if ~isstruct(C) || ~isfield(C, 'filter') || isempty(C.filter)
    obj.set_status_('No equalization filter to copy. Design or load one first.', true);
    return
end

filt = C.filter;
if ~isfir(filt)
    obj.set_status_(['This filter is not FIR, so it has no single tap list. ' ...
        'Redesign it, or read the coefficients from the .esgc file.'], true);
    return
end
b = tf(filt);

% %.17g round-trips a double exactly. The taps are the calibration
% once they leave here -- whatever reads them back has no way to
% recover a digit this print drops.
if ispc
    eol = sprintf('\r\n');   % Notepad and RPvds want CRLF
else
    eol = newline;
end
txt = strjoin(compose('%.17g', b(:)), eol);

try
    clipboard('copy', char(txt));
catch ME
    stimgen.util.vprintf(0, 1, ME);
    obj.set_status_(sprintf('Could not write to the clipboard: %s', ME.message), true);
    return
end

fs = obj.filter_design_rate_();
if fs > 0
    % %.10g: 24414.0625 is a real converter rate, and a filter is
    % only its designed response at the rate it was cut for.
    msg = sprintf('%d filter coefficients copied to the clipboard (designed for Fs = %.10g Hz).', ...
        numel(b), fs);
else
    msg = sprintf('%d filter coefficients copied to the clipboard.', numel(b));
end
obj.set_status_(msg, false);
end
