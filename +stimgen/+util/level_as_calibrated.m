function m = level_as_calibrated(y, fs, req, micSens, spectral)
% m = stimgen.util.level_as_calibrated(y, fs, req)
% m = stimgen.util.level_as_calibrated(y, fs, req, micSens)
% m = stimgen.util.level_as_calibrated(y, fs, req, micSens, spectral)
% Measure a recording the way the table that calibrated its stimulus was
% measured, and compare the result with the level the stimulus asked for.
%
% The half of the rule that reads the recording; stimgen.util.level_request is
% the half that reads the stimulus, and its header says why the measurement
% has to follow the stimulus's calibration type. Measurements are made in
% volts exactly as Engine/measure_ makes them -- spectral rms, peak, or rms --
% and a peak is converted to its rms equivalent (divided by sqrt 2) before it
% becomes a level, which is what Engine/compute_spl_voltage_ does when it
% builds the click table, so the two land on one scale.
%
% The level itself goes through stimgen.calibration.Engine.volts_to_spl, the
% package's one conversion from volts to dB SPL. Without a microphone
% sensitivity there is no dB SPL to report; the measurement in volts (and in
% dB re 1 V) is still returned, because it is still true.
%
% spectral must be the options the calibration measured with (Engine's
% spectral_options) for a "specfreq" measurement to reproduce the table's
% own estimate; the default is what an unconfigured engine uses.
%
% Parameters:
%   y        - (1,:) double recorded response (V), cut to the stimulus span
%   fs       - (1,1) double sample rate (Hz)
%   req      - (1,1) struct from stimgen.util.level_request. A struct missing
%              its fields (an unknown request) is measured as broadband rms
%              with nothing to compare against.
%   micSens  - (1,1) double microphone sensitivity (V/Pa); NaN (default) for
%              none
%   spectral - (1,1) stimgen.calibration.SpectralOptions (default: auto)
%
% Returns:
%   m - struct:
%     mode             "specfreq" | "peak" | "rms", as actually measured
%     frequency_hz     anchor used by "specfreq"; NaN otherwise
%     level_reference  (1,1) string, the measurement in words
%     measurement_v    the measurement itself (V): spectral rms, peak or rms
%     rms_v            its rms equivalent (V)
%     level_db         dB SPL of rms_v; NaN without a sensitivity
%     level_dbv        dB re 1 V of rms_v
%     requested_db     the level asked for; NaN when unknown
%     calibrated       the requested level is a real dB SPL
%     error_db         level_db - requested_db when both are real; else NaN
%
% See also: stimgen.util.level_request, stimgen.calibration.Engine.volts_to_spl,
%           stimgen.calibration.Engine.spectral_rms
arguments
    y        (1,:) double
    fs       (1,1) double {mustBePositive, mustBeFinite}
    req      (1,1) struct
    micSens  (1,1) double = nan
    spectral (1,1) stimgen.calibration.SpectralOptions = ...
        stimgen.calibration.SpectralOptions()
end

mode     = field_(req, 'mode', "rms");
anchorHz = field_(req, 'frequency_hz', nan);

if mode == "specfreq" && ~(isfinite(anchorHz) && anchorHz > 0 && anchorHz < fs / 2)
    % An anchor at or past Nyquist is not in the record; measuring the bin
    % nearest to it would report something else under its name.
    mode     = "rms";
    anchorHz = nan;
end

y = y(isfinite(y));

switch mode
    case "specfreq"
        if numel(y) < 2
            meas = 0;
        else
            meas = stimgen.calibration.Engine.spectral_rms(y, anchorHz, fs, ...
                Spectral = spectral);
        end
        rmsV = meas;
    case "peak"
        meas = max([abs(y), 0]);
        rmsV = meas / sqrt(2);
    otherwise
        mode = "rms";
        if isempty(y)
            meas = 0;
        else
            meas = sqrt(mean(y .^ 2));
        end
        rmsV = meas;
end

if isfinite(micSens) && micSens > 0
    levelDb = stimgen.calibration.Engine.volts_to_spl(rmsV, micSens);
else
    levelDb = nan;
end

requested  = field_(req, 'level_db', nan);
calibrated = logical(field_(req, 'calibrated', false));
if calibrated && isfinite(requested) && isfinite(levelDb)
    errorDb = levelDb - requested;
else
    errorDb = nan;
end

m = struct( ...
    'mode',            mode, ...
    'frequency_hz',    anchorHz, ...
    'level_reference', describe_(mode, anchorHz), ...
    'measurement_v',   meas, ...
    'rms_v',           rmsV, ...
    'level_db',        levelDb, ...
    'level_dbv',       20 * log10(max(rmsV, realmin)), ...
    'requested_db',    requested, ...
    'calibrated',      calibrated, ...
    'error_db',        errorDb);
end


% ------------------------------------------------------------------------ %
function text = describe_(mode, anchorHz)
% The measurement in words, for a table row or a status line.
switch mode
    case "specfreq"
        text = string(sprintf('spectral rms at %.4g Hz', anchorHz));
    case "peak"
        text = "peak, as rms equivalent";
    otherwise
        text = "broadband rms";
end
end


function v = field_(s, name, default)
% A request field, or the default when an unknown request lacks it.
if isfield(s, name) && ~isempty(s.(name))
    v = s.(name);
    if isstring(default) || ischar(default)
        v = string(v);
    elseif isnumeric(default)
        v = double(v);
    end
else
    v = default;
end
end
