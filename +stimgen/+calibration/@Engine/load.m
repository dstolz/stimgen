function [eng, ffn] = load(ffn)
% eng = stimgen.calibration.Engine.load()
% eng = stimgen.calibration.Engine.load(ffn)
% [eng, ffn] = stimgen.calibration.Engine.load(...)
%
% Load a .esgc calibration file and return an Engine with no
% adapter attached. Suitable for offline compute_adjusted_voltage
% use. Attach an adapter to run new calibrations.
%
% Parameters:
%   ffn - full file path (char, optional); prompts if omitted
%
% Returns:
%   eng - stimgen.calibration.Engine, or [] if the load dialog was cancelled
%   ffn - resolved file path; empty if the load dialog was cancelled
arguments
    ffn (1,:) char = ''
end
if isempty(ffn)
    pn = getpref('StimCalibration', 'path', pwd);
    [fn, pn] = uigetfile( ...
        {'*.esgc','EPsych Stim Calibration (*.esgc)'}, ...
        'Load Calibration', pn);
    if isequal(fn, 0), eng = []; return; end
    ffn = fullfile(pn, fn);
    setpref('StimCalibration', 'path', pn);
end

[~, ~, ext] = fileparts(ffn);
if ~strcmpi(ext, '.esgc')
    error('stimgen:calibration:Engine:wrongFormat', ...
        ['Expected a .esgc file. Old .sgc files are not supported - ' ...
        'please recalibrate and save to a new .esgc file.']);
end

s = load(ffn, '-mat');
if ~isfield(s, 'version')
    error('stimgen:calibration:Engine:missingVersion', ...
        'File "%s" is missing the schema version field.', ffn);
end

eng = stimgen.calibration.Engine();
eng.restore_from_struct_(s);

if isstruct(eng.CalibrationData)
    % isnat, not isequal against datetime(""): NaT compares unequal to itself
    % the way NaN does, so the isequal form never caught the case. Reachable
    % for a file holding only a background capture, which does not re-date the
    % transfer measurements and so leaves the timestamp unset.
    ts = eng.CalibrationTimestamp;
    if isnat(ts)
        stimgen.util.vprintf(0, 'Loaded calibration: "%s" (timestamp unknown)', ffn);
    else
        stimgen.util.vprintf(0, 'Loaded calibration: "%s" from %s', ffn, string(ts));
    end
end
end
