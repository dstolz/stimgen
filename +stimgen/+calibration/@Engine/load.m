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

warn_if_stale_spl_scale_(s, ffn);

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


% ------------------------------------------------------------------------ %
function warn_if_stale_spl_scale_(s, ffn)
% warn_if_stale_spl_scale_(s, ffn)
% Say so when a file's tables were built on the pre-v2 level scale.
%
% Version 1 computed dB SPL as ReferenceLevel + 20*log10(v/MicSensitivity),
% which added the calibrator's own output level to a scale that is defined by
% the 20 uPa reference and nothing else -- counting the calibrator twice, once
% in the sensitivity and again in every level derived from it.
%
% The error is exactly (ReferenceLevel - 94) dB, so a file taken at the default
% 94 dB calibrator setting is unaffected and passes silently. A file taken at
% 114 dB has drive voltages 20 dB too low and will play that much too quietly.
%
% Reported rather than corrected. The correction is arithmetic --
% CalibrationData tone/click/swept_sine voltages scale by
% 10^((ReferenceLevel-94)/20) and their spl_db shift by -(ReferenceLevel-94) --
% but a rig whose levels were visibly wrong may already have been compensated
% somewhere else, and silently moving measurement data underneath a user who
% cannot see it happen is worse than telling them plainly.

if ~isfield(s, 'version') || s.version >= 2
    return
end
if ~isfield(s, 'ReferenceLevel') || isempty(s.ReferenceLevel)
    return
end

offsetDb = s.ReferenceLevel - 94;
if abs(offsetDb) < 0.05
    return      % the default calibrator; version 1 and 2 agree
end

stimgen.util.vprintf(0, 1, ...
    ['Calibration "%s" was saved on the old level scale, which added the ' ...
     '%.1f dB calibrator level on top of the 20 uPa reference. Every level ' ...
     'in it is %+.1f dB off and its drive voltages are %+.1f dB the other ' ...
     'way, so this rig would play about %.1f dB too %s. Re-run the reference ' ...
     'and the sweeps to rebuild it.'], ...
    ffn, s.ReferenceLevel, offsetDb, -offsetDb, abs(offsetDb), ...
    ternary_(offsetDb > 0, 'quietly', 'loudly'));
end


function out = ternary_(cond, a, b)
if cond
    out = a;
else
    out = b;
end
end
